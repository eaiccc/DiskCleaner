//
//  AppStore.swift
//  DiskCleaner
//
//  Observable app state: disk info, scanning, candidates, cleaning basket and cleanup flow.
//

import Foundation
import SwiftUI
import SwiftData
import AppKit

enum CleanupPhase: Equatable {
    case idle, confirming, running, finished
}

struct CleanupReport {
    let batchID: UUID
    var result: CleanupResult
    let estimated: Int64
    var actualFreed: Int64
    var trashedSize: Int64
}

struct CategorySummary {
    var total: Int64 = 0
    var safeTotal: Int64 = 0
    var count = 0
}

@Observable
final class AppStore {
    static let shared = AppStore()

    // MARK: Disk & permission
    var disk = DiskInfo.read()
    var hasFullDiskAccess = FullDiskAccess.isGranted()
    var fdaBannerDismissed = false

    var isLowSpace: Bool { disk.total > 0 && Double(disk.available) / Double(disk.total) < 0.10 }

    // MARK: Scan state
    var isTreeScanning = false
    var isRuleScanning = false
    var isScanning: Bool { isTreeScanning || isRuleScanning }
    var scannedFiles = 0
    var scannedBytes: Int64 = 0
    var currentPath = ""
    var root: FileNode?
    /// Bumped whenever `root` is replaced so views can re-resolve stale node references.
    var rootVersion = 0
    var lastScanDate: Date?
    var isSnapshotData = false

    var ruleCandidates: [CleanupCandidate] = []
    var treeCandidates: [CleanupCandidate] = []
    var largeFiles: [FileNode] = []
    var candidates: [CleanupCandidate] { ruleCandidates + treeCandidates }

    // MARK: Basket
    var basket: [String: CleanupCandidate] = [:]
    var basketItems: [CleanupCandidate] { CleanupPlanner.normalize(Array(basket.values)) }

    // MARK: Cleanup flow
    var cleanupPhase: CleanupPhase = .idle
    var pendingItems: [CleanupCandidate] = []
    var runningAppWarnings: [String] = []
    var cleanupProgress = 0.0
    var cleanupCurrent = ""
    var report: CleanupReport?

    var modelContainer: ModelContainer?

    // MARK: Exclusions
    var excludedPaths: [String] = UserDefaults.standard.stringArray(forKey: "excludedPaths") ?? [] {
        didSet {
            UserDefaults.standard.set(excludedPaths, forKey: "excludedPaths")
            ruleEngine = RuleEngine(excluded: excludedPaths)
        }
    }

    private(set) var ruleEngine: RuleEngine
    private var ruleTask: Task<Void, Never>?
    private var treeTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?
    private var diskTimer: Task<Void, Never>?
    private var partialChildren: [FileNode] = []
    private var didLaunch = false

    private init() {
        ruleEngine = RuleEngine(excluded: UserDefaults.standard.stringArray(forKey: "excludedPaths") ?? [])
    }

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    // MARK: - Lifecycle

    func onLaunch() {
        guard !didLaunch else { return }
        didLaunch = true
        diskTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.refreshDisk()
            }
        }
        guard !AppStore.isRunningTests else { return }
        Task {
            let snapshot = await Task.detached(priority: .utility) { SnapshotStore.load() }.value
            if let snapshot, self.root == nil {
                self.applyTree(snapshot.root, date: snapshot.date, fromSnapshot: true)
            }
            self.startScan()
        }
    }

    func refreshDisk() {
        disk = DiskInfo.read()
    }

    func recheckPermission() {
        let granted = FullDiskAccess.isGranted()
        if granted && !hasFullDiskAccess && didLaunch {
            hasFullDiskAccess = true
            startScan()
        } else {
            hasFullDiskAccess = granted
        }
    }

    // MARK: - Scanning

    func startScan() {
        cancelScan()
        refreshDisk()
        hasFullDiskAccess = FullDiskAccess.isGranted()
        scanRules()
        scanTree()
    }

    func cancelScan() {
        ruleTask?.cancel()
        treeTask?.cancel()
        progressTask?.cancel()
        isRuleScanning = false
        isTreeScanning = false
    }

    func scanRules() {
        ruleTask?.cancel()
        isRuleScanning = true
        let engine = ruleEngine
        ruleTask = Task.detached(priority: .userInitiated) { [weak self] in
            print("AppStore [LOG]: rule scan started (\(engine.rules.count) rules)")
            var found = engine.evaluate()
            let simulators = SimulatorService()
            found += simulators.deviceCandidates()
            found += simulators.runtimeCandidates()
            let excluded = engine.excluded
            found.removeAll { c in excluded.contains { PathUtils.isSameOrInside(c.path, $0) } }
            if Task.isCancelled { return }
            print("AppStore [LOG]: rule scan finished, \(found.count) candidates")
            let sorted = found.sorted { $0.size > $1.size }
            await self?.finishRuleScan(sorted)
        }
    }

    private func finishRuleScan(_ found: [CleanupCandidate]) {
        ruleCandidates = found
        isRuleScanning = false
        refreshBasket()
    }

    func scanTree() {
        treeTask?.cancel()
        progressTask?.cancel()
        isTreeScanning = true
        scannedFiles = 0
        scannedBytes = 0
        partialChildren = []
        let scanner = DiskScanner()
        let progress = scanner.progress
        let volumeName = disk.name
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                let s = progress.snapshot
                self?.scannedFiles = s.files
                self?.scannedBytes = s.bytes
                self?.currentPath = s.current
            }
        }
        treeTask = Task.detached(priority: .userInitiated) { [weak self] in
            let started = Date()
            print("AppStore [LOG]: full disk scan started")
            let root = await scanner.scan(root: "/", rootName: volumeName) { child in
                await self?.addPartial(child)
            }
            if Task.isCancelled { return }
            print("AppStore [LOG]: full disk scan finished in \(Int(Date().timeIntervalSince(started)))s, \(root.size.formattedSize())")
            await self?.finishTreeScan(root)
        }
    }

    private func addPartial(_ child: FileNode) {
        // Only show progressive results when there is nothing better (no snapshot) on screen.
        guard isTreeScanning, root == nil || !isSnapshotData else { return }
        partialChildren.append(child)
        root = FileNode.makeRoot(name: disk.name, children: partialChildren)
        rootVersion += 1
    }

    private func finishTreeScan(_ newRoot: FileNode) {
        progressTask?.cancel()
        let s = (scannedFiles, scannedBytes)
        _ = s
        isTreeScanning = false
        applyTree(newRoot, date: Date(), fromSnapshot: false)
        Task.detached(priority: .background) {
            SnapshotStore.save(newRoot, date: Date())
        }
    }

    private func applyTree(_ newRoot: FileNode, date: Date, fromSnapshot: Bool) {
        root = newRoot
        rootVersion += 1
        lastScanDate = date
        isSnapshotData = fromSnapshot
        let home = PathUtils.home
        let excluded = excludedPaths
        Task {
            let (artifacts, large) = await Task.detached(priority: .utility) {
                let artifacts = TreeAnalyzer.projectArtifacts(root: newRoot, home: home)
                    .filter { c in !excluded.contains { PathUtils.isSameOrInside(c.path, $0) } }
                let large = TreeAnalyzer.largeFiles(root: newRoot, minSize: 100 << 20)
                    .filter { n in !excluded.contains { PathUtils.isSameOrInside(n.path, $0) } }
                return (artifacts, large)
            }.value
            self.treeCandidates = artifacts
            self.largeFiles = large
            self.refreshBasket()
        }
    }

    // MARK: - Summaries

    func summary(for categories: Set<CleanupCategory>) -> CategorySummary {
        var s = CategorySummary()
        for c in candidates where categories.contains(c.category) {
            s.total += c.size
            s.count += 1
            if c.safety == .safe { s.safeTotal += c.size }
        }
        if categories.contains(.largeFiles) {
            for f in largeFiles {
                s.total += f.size
                s.count += 1
            }
        }
        return s
    }

    var safeCandidates: [CleanupCandidate] { candidates.filter { $0.safety == .safe } }

    func classify(_ path: String) -> CleanupRule? { ruleEngine.classify(path) }

    /// Wraps an arbitrary scanned node as a cleanup candidate.
    func candidate(for node: FileNode) -> CleanupCandidate {
        if let existing = candidates.first(where: { $0.path == node.path }) { return existing }
        let rule = classify(node.path)
        let safety = rule?.safety ?? .review
        return CleanupCandidate(
            path: node.path, name: node.name, detail: PathUtils.abbreviate(node.path), size: node.size,
            lastModified: node.modified, safety: safety,
            category: rule?.category ?? (node.isDirectory ? .custom : .largeFiles),
            ruleID: rule?.id ?? "custom", ruleName: rule?.name ?? "自選項目", note: rule?.note,
            runningApps: rule?.runningApps ?? [])
    }

    // MARK: - Basket

    func isInBasket(_ candidate: CleanupCandidate) -> Bool { basket[candidate.id] != nil }

    func setInBasket(_ candidate: CleanupCandidate, _ included: Bool) {
        if included { basket[candidate.id] = candidate } else { basket[candidate.id] = nil }
    }

    func addToBasket(_ items: [CleanupCandidate]) {
        for item in items { basket[item.id] = item }
    }

    func removeFromBasket(_ items: [CleanupCandidate]) {
        for item in items { basket[item.id] = nil }
    }

    func clearBasket() { basket.removeAll() }

    /// Refreshes basket entries with fresh candidate data and drops entries whose files are gone.
    private func refreshBasket() {
        let byID = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for (id, item) in basket {
            if let fresh = byID[id] {
                basket[id] = fresh
            } else if item.hasFilesystemPath && FS.entry(at: item.path) == nil {
                basket[id] = nil
            }
        }
    }

    // MARK: - Exclusions

    func exclude(_ path: String) {
        guard !excludedPaths.contains(path) else { return }
        excludedPaths.append(path)
        ruleCandidates.removeAll { PathUtils.isSameOrInside($0.path, path) }
        treeCandidates.removeAll { PathUtils.isSameOrInside($0.path, path) }
        largeFiles.removeAll { PathUtils.isSameOrInside($0.path, path) }
        for (id, item) in basket where PathUtils.isSameOrInside(item.path, path) { basket[id] = nil }
    }

    func removeExclusion(_ path: String) {
        excludedPaths.removeAll { $0 == path }
    }

    // MARK: - Cleanup flow

    func beginCleanup(_ items: [CleanupCandidate]) {
        let normalized = CleanupPlanner.normalize(items)
        guard !normalized.isEmpty else { return }
        pendingItems = normalized
        runningAppWarnings = RunningApps.names(for: Set(normalized.flatMap(\.runningApps)))
        cleanupPhase = .confirming
    }

    func cancelConfirmation() {
        pendingItems = []
        cleanupPhase = .idle
    }

    func performCleanup() {
        let items = pendingItems
        guard !items.isEmpty else { return }
        cleanupPhase = .running
        cleanupProgress = 0
        cleanupCurrent = ""
        let freeBefore = DiskInfo.read().availableNow
        let executor = CleanupExecutor()
        cleanupTask = Task.detached(priority: .userInitiated) { [weak self] in
            let result = executor.run(items) { progress, current in
                Task { @MainActor in
                    self?.cleanupProgress = progress
                    self?.cleanupCurrent = current
                }
            }
            await self?.finishCleanup(result, estimated: CleanupPlanner.totalSize(items), freeBefore: freeBefore)
        }
    }

    func cancelCleanup() {
        cleanupTask?.cancel()
    }

    private func finishCleanup(_ result: CleanupResult, estimated: Int64, freeBefore: Int64) {
        let batchID = UUID()
        if let context = modelContainer?.mainContext {
            for outcome in result.done {
                let c = outcome.candidate
                context.insert(CleanupRecord(batchID: batchID, name: c.name, originalPath: c.path,
                                             trashPath: outcome.trashPath, fileSize: c.size,
                                             category: c.category.rawValue, safety: c.safety.rawValue,
                                             actionKind: c.action.kind))
            }
            try? context.save()
        }

        let removedIDs = Set(result.done.map(\.candidate.id))
        let removedPaths = Set(result.done.map(\.candidate.path).filter { $0.hasPrefix("/") })
        ruleCandidates.removeAll { removedIDs.contains($0.id) }
        treeCandidates.removeAll { removedIDs.contains($0.id) }
        largeFiles.removeAll { removedPaths.contains($0.path) }
        for id in removedIDs { basket[id] = nil }
        if let current = root, !removedPaths.isEmpty {
            root = current.removing(removedPaths) ?? current
            rootVersion += 1
        }

        refreshDisk()
        let freed = max(0, disk.availableNow - freeBefore)
        report = CleanupReport(batchID: batchID, result: result, estimated: result.processedSize,
                               actualFreed: freed, trashedSize: result.trashedSize)
        pendingItems = []
        cleanupPhase = .finished
        print("AppStore [LOG]: cleanup done \(result.done.count) ok, \(result.failed.count) failed, freed \(freed.formattedSize())")
    }

    /// Permanently deletes the items the last cleanup moved to the Trash (frees their space).
    func purgeTrashedItemsOfLastReport() {
        guard var report else { return }
        let paths = report.result.done.compactMap(\.trashPath)
        let freeBefore = DiskInfo.read().availableNow
        Task {
            await Task.detached(priority: .userInitiated) {
                for path in paths { try? FileManager.default.removeItem(atPath: path) }
            }.value
            if let context = self.modelContainer?.mainContext {
                let batchID = report.batchID
                let descriptor = FetchDescriptor<CleanupRecord>(predicate: #Predicate { $0.batchID == batchID })
                for record in (try? context.fetch(descriptor)) ?? [] where record.actionKind == "trash" {
                    record.actionKind = "delete"
                    record.trashPath = nil
                }
                try? context.save()
            }
            self.refreshDisk()
            report.actualFreed += max(0, self.disk.availableNow - freeBefore)
            report.trashedSize = 0
            self.report = report
        }
    }

    func dismissCleanup() {
        cleanupPhase = .idle
        report = nil
    }

    // MARK: - History

    /// Moves a trashed item back to its original location. Returns an error message on failure.
    func restore(_ record: CleanupRecord) -> String? {
        guard let trashPath = record.trashPath, record.canRestore else { return "垃圾桶中已找不到此項目" }
        let fm = FileManager.default
        if fm.fileExists(atPath: record.originalPath) { return "原位置已有同名檔案：\(record.originalPath)" }
        do {
            try fm.createDirectory(atPath: PathUtils.parent(record.originalPath), withIntermediateDirectories: true)
            try fm.moveItem(atPath: trashPath, toPath: record.originalPath)
            record.restored = true
            try? modelContainer?.mainContext.save()
            refreshDisk()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func purgeOldRecords(olderThanDays days: Int = 30) {
        guard let context = modelContainer?.mainContext else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let descriptor = FetchDescriptor<CleanupRecord>(predicate: #Predicate { $0.timestamp < cutoff })
        for record in (try? context.fetch(descriptor)) ?? [] { context.delete(record) }
        try? context.save()
    }
}
