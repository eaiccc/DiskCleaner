//
//  CleanupExecutor.swift
//  DiskCleaner
//
//  Plans and executes cleanup: delete / move to Trash / simctl.
//

import Foundation

nonisolated enum CleanupPlanner {
    /// Removes duplicates and items already covered by a selected ancestor folder, largest first.
    static func normalize(_ items: [CleanupCandidate]) -> [CleanupCandidate] {
        var seenIDs = Set<String>()
        var claimedPaths: [String] = []
        var kept: [CleanupCandidate] = []
        for item in items.sorted(by: { $0.path.count < $1.path.count }) {
            guard seenIDs.insert(item.id).inserted else { continue }
            if item.hasFilesystemPath {
                if claimedPaths.contains(where: { PathUtils.isSameOrInside(item.path, $0) }) { continue }
                claimedPaths.append(item.path)
            }
            kept.append(item)
        }
        return kept.sorted { $0.size > $1.size }
    }

    static func totalSize(_ items: [CleanupCandidate]) -> Int64 {
        items.reduce(0) { $0 + $1.size }
    }
}

nonisolated struct CleanupOutcome: Identifiable, Sendable {
    let candidate: CleanupCandidate
    /// Location in the Trash for `.trash` actions (enables "put back").
    let trashPath: String?
    var id: String { candidate.id }
}

nonisolated struct CleanupFailure: Identifiable, Sendable {
    let candidate: CleanupCandidate
    let message: String
    var id: String { candidate.id }
}

nonisolated struct CleanupResult: Sendable {
    var done: [CleanupOutcome] = []
    var failed: [CleanupFailure] = []
    var cancelled = false

    var processedSize: Int64 { done.reduce(0) { $0 + $1.candidate.size } }
    var trashedSize: Int64 { done.filter { $0.trashPath != nil }.reduce(0) { $0 + $1.candidate.size } }
}

nonisolated enum CleanupError: LocalizedError {
    case protectedPath(String)
    case missing(String)
    case simctl(String)

    var errorDescription: String? {
        switch self {
        case .protectedPath(let p): return "受保護的路徑，已拒絕：\(p)"
        case .missing(let p): return "找不到檔案：\(p)"
        case .simctl(let message): return "simctl 失敗：\(message)"
        }
    }
}

nonisolated struct CleanupExecutor: Sendable {
    var home: String = PathUtils.home
    var tmpDir: String = PathUtils.tmpDir

    func run(_ items: [CleanupCandidate], progress: @Sendable (Double, String) -> Void) -> CleanupResult {
        var result = CleanupResult()
        for (index, item) in items.enumerated() {
            if Task.isCancelled {
                result.cancelled = true
                break
            }
            progress(Double(index) / Double(max(items.count, 1)), item.name)
            do {
                let trashPath = try perform(item)
                result.done.append(CleanupOutcome(candidate: item, trashPath: trashPath))
            } catch {
                print("CleanupExecutor [ERROR]: \(item.path): \(error.localizedDescription)")
                result.failed.append(CleanupFailure(candidate: item, message: error.localizedDescription))
            }
        }
        progress(1, "")
        return result
    }

    /// Returns the Trash location for `.trash`, nil otherwise.
    func perform(_ item: CleanupCandidate) throws -> String? {
        let fm = FileManager.default
        switch item.action {
        case .delete:
            try checkPath(item.path)
            try fm.removeItem(atPath: item.path)
            return nil
        case .trash:
            try checkPath(item.path)
            var resulting: NSURL?
            try fm.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: &resulting)
            return resulting?.path
        case .simctlDeleteDevice(let udid):
            Simctl.run(["simctl", "shutdown", udid])
            let r = Simctl.run(["simctl", "delete", udid])
            guard r.status == 0 else { throw CleanupError.simctl(r.error) }
            return nil
        case .simctlDeleteRuntime(let identifier):
            let r = Simctl.run(["simctl", "runtime", "delete", identifier])
            guard r.status == 0 else { throw CleanupError.simctl(r.error) }
            return nil
        }
    }

    private func checkPath(_ path: String) throws {
        guard PathGuard.isDeletionAllowed(path, home: home, tmpDir: tmpDir) else {
            throw CleanupError.protectedPath(path)
        }
        guard FS.entry(at: path) != nil else { throw CleanupError.missing(path) }
    }
}
