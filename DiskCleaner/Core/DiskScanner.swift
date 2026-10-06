//
//  DiskScanner.swift
//  DiskCleaner
//
//  Parallel whole-disk scanner that builds an immutable FileNode tree.
//

import Foundation
import Synchronization

/// Immutable tree node. Directories smaller than the prune threshold keep their size but drop children
/// to bound memory; files smaller than the keep threshold are merged into a single aggregate child.
nonisolated final class FileNode: Identifiable, Hashable, Sendable, Codable {
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64
    let itemCount: Int
    let modified: Date?
    let isAggregate: Bool
    let children: [FileNode]

    init(name: String, path: String, isDirectory: Bool, size: Int64, itemCount: Int,
         modified: Date?, isAggregate: Bool = false, children: [FileNode] = []) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
        self.itemCount = itemCount
        self.modified = modified
        self.isAggregate = isAggregate
        self.children = children
    }

    private enum CodingKeys: String, CodingKey {
        case name = "n", path = "p", isDirectory = "d", size = "s", itemCount = "c"
        case modified = "m", isAggregate = "a", children = "k"
    }

    var id: String { path }

    /// For hierarchical `Table` rows.
    var optionalChildren: [FileNode]? { children.isEmpty ? nil : children }

    static func == (lhs: FileNode, rhs: FileNode) -> Bool {
        lhs === rhs || (lhs.path == rhs.path && lhs.size == rhs.size && lhs.children.count == rhs.children.count)
    }

    func hash(into hasher: inout Hasher) { hasher.combine(path) }

    /// Finds a descendant (or self) by absolute path.
    func node(at target: String) -> FileNode? {
        if target == path { return self }
        guard PathUtils.isSameOrInside(target, path) else { return nil }
        for child in children where PathUtils.isSameOrInside(target, child.path) {
            return child.node(at: target)
        }
        return nil
    }

    /// Returns a copy of the tree without the given paths, with ancestor sizes adjusted.
    func removing(_ removed: Set<String>) -> FileNode? {
        if removed.contains(path) { return nil }
        guard !children.isEmpty, removed.contains(where: { PathUtils.isSameOrInside($0, path) }) else { return self }
        var kept: [FileNode] = []
        var sizeDelta: Int64 = 0
        var countDelta = 0
        for child in children {
            if let updated = child.removing(removed) {
                kept.append(updated)
                sizeDelta += child.size - updated.size
                countDelta += child.itemCount - updated.itemCount
            } else {
                sizeDelta += child.size
                countDelta += child.itemCount + (child.isDirectory ? 1 : 0)
            }
        }
        return FileNode(name: name, path: path, isDirectory: isDirectory, size: max(0, size - sizeDelta),
                        itemCount: max(0, itemCount - countDelta), modified: modified,
                        isAggregate: isAggregate, children: kept.sorted { $0.size > $1.size })
    }

    /// Copy that drops nodes smaller than `minSize` (used for the on-disk snapshot).
    func pruned(minSize: Int64) -> FileNode {
        FileNode(name: name, path: path, isDirectory: isDirectory, size: size, itemCount: itemCount,
                 modified: modified, isAggregate: isAggregate,
                 children: children.filter { $0.size >= minSize }.map { $0.pruned(minSize: minSize) })
    }

    static func makeRoot(name: String, children: [FileNode]) -> FileNode {
        let sorted = children.sorted { $0.size > $1.size }
        return FileNode(name: name, path: "/", isDirectory: true,
                        size: sorted.reduce(0) { $0 + $1.size },
                        itemCount: sorted.reduce(0) { $0 + $1.itemCount + ($1.isDirectory ? 1 : 0) },
                        modified: nil, children: sorted)
    }
}

/// Thread-safe progress counters polled by the UI.
nonisolated final class ScanProgress: Sendable {
    struct State: Sendable {
        var files = 0
        var bytes: Int64 = 0
        var current = ""
    }

    private let state = Mutex(State())

    func add(files: Int, bytes: Int64, current: String) {
        state.withLock {
            $0.files += files
            $0.bytes += bytes
            $0.current = current
        }
    }

    var snapshot: State { state.withLock { $0 } }
}

/// De-duplicates hard links so their data is only counted once.
nonisolated final class InodeSet: Sendable {
    private struct Key: Hashable { let device: Int32; let inode: UInt64 }
    private let seen = Mutex(Set<Key>())

    /// Returns `true` the first time a (device, inode) pair is seen.
    func insert(device: Int32, inode: UInt64) -> Bool {
        seen.withLock { $0.insert(Key(device: device, inode: inode)).inserted }
    }
}

nonisolated struct DiskScanner: Sendable {
    /// Paths that are never descended into: duplicated firmlink trees, other volumes,
    /// and the magic `/.nofollow` / `/.resolve` aliases of `/` (macOS 15+).
    static let defaultSkipPaths: Set<String> = [
        "/System/Volumes/Data", "/Volumes", "/dev", "/net", "/home", "/Network",
        "/.vol", "/.nofollow", "/.resolve", "/.MobileBackups", "/.Spotlight-V100", "/.fseventsd"
    ]

    var skipPaths: Set<String> = DiskScanner.defaultSkipPaths
    var keepFileThreshold: Int64 = 1 << 20
    var pruneDirectoryThreshold: Int64 = 1 << 20
    var parallelDepth = 3

    let progress = ScanProgress()
    let inodes = InodeSet()

    /// Scans `root`. `onTopLevel` is invoked as each first-level child completes (progressive UI).
    func scan(root: String, rootName: String,
              onTopLevel: (@Sendable (FileNode) async -> Void)? = nil) async -> FileNode {
        let ownSize = FS.entry(at: root)?.allocated ?? 0
        return await scanDirectory(path: root, name: rootName, ownSize: ownSize, ownModified: nil,
                                   depth: 0, onChild: onTopLevel)
    }

    private struct Accumulator {
        var fileNodes: [FileNode] = []
        var smallSize: Int64 = 0
        var smallCount = 0
        var fileCount = 0
        var fileBytes: Int64 = 0
        var newest: Date?
        var subdirectories: [DirEntry] = []
    }

    private func collect(_ path: String) -> Accumulator? {
        guard let entries = FS.list(path) else { return nil }
        var acc = Accumulator()
        for e in entries {
            if e.isDirectory {
                if !skipPaths.contains(e.path) { acc.subdirectories.append(e) }
                continue
            }
            var size = e.allocated
            if e.linkCount > 1 && !inodes.insert(device: e.device, inode: e.inode) {
                size = 0
            }
            acc.fileCount += 1
            acc.fileBytes += size
            if acc.newest == nil || e.modified > acc.newest! { acc.newest = e.modified }
            if size >= keepFileThreshold {
                acc.fileNodes.append(FileNode(name: e.name, path: e.path, isDirectory: false,
                                              size: size, itemCount: 0, modified: e.modified))
            } else {
                acc.smallSize += size
                acc.smallCount += 1
            }
        }
        progress.add(files: acc.fileCount, bytes: acc.fileBytes, current: path)
        return acc
    }

    private func scanDirectory(path: String, name: String, ownSize: Int64, ownModified: Date?,
                               depth: Int, onChild: (@Sendable (FileNode) async -> Void)?) async -> FileNode {
        guard !Task.isCancelled, let acc = collect(path) else {
            return FileNode(name: name, path: path, isDirectory: true, size: ownSize, itemCount: 0, modified: ownModified)
        }
        var directories: [FileNode] = []
        if depth < parallelDepth && acc.subdirectories.count > 1 {
            directories = await withTaskGroup(of: FileNode.self) { group in
                for sub in acc.subdirectories {
                    group.addTask {
                        await self.scanDirectory(path: sub.path, name: sub.name, ownSize: sub.allocated,
                                                 ownModified: sub.modified, depth: depth + 1, onChild: nil)
                    }
                }
                var nodes: [FileNode] = []
                for await node in group {
                    nodes.append(node)
                    if let onChild { await onChild(node) }
                }
                return nodes
            }
        } else {
            for sub in acc.subdirectories {
                let node = scanDirectorySync(path: sub.path, name: sub.name, ownSize: sub.allocated, ownModified: sub.modified)
                directories.append(node)
                if let onChild { await onChild(node) }
            }
        }
        return makeNode(name: name, path: path, ownSize: ownSize, ownModified: ownModified, acc: acc, directories: directories)
    }

    private func scanDirectorySync(path: String, name: String, ownSize: Int64, ownModified: Date?) -> FileNode {
        guard !Task.isCancelled, let acc = collect(path) else {
            return FileNode(name: name, path: path, isDirectory: true, size: ownSize, itemCount: 0, modified: ownModified)
        }
        let directories = acc.subdirectories.map {
            scanDirectorySync(path: $0.path, name: $0.name, ownSize: $0.allocated, ownModified: $0.modified)
        }
        return makeNode(name: name, path: path, ownSize: ownSize, ownModified: ownModified, acc: acc, directories: directories)
    }

    private func makeNode(name: String, path: String, ownSize: Int64, ownModified: Date?,
                          acc: Accumulator, directories: [FileNode]) -> FileNode {
        var children = directories + acc.fileNodes
        let total = ownSize + acc.smallSize + children.reduce(0) { $0 + $1.size }
        let count = acc.fileCount + directories.reduce(0) { $0 + $1.itemCount + 1 }
        var newest = acc.newest
        for candidate in [ownModified] + directories.map(\.modified) {
            if let c = candidate, newest == nil || c > newest! { newest = c }
        }
        if total < pruneDirectoryThreshold {
            children = []
        } else {
            if acc.smallCount > 0 {
                children.append(FileNode(name: "\(acc.smallCount) 個小檔案", path: PathUtils.join(path, "\u{2026}small-files"),
                                         isDirectory: false, size: acc.smallSize, itemCount: acc.smallCount,
                                         modified: acc.newest, isAggregate: true))
            }
            children.sort { $0.size > $1.size }
        }
        return FileNode(name: name, path: path, isDirectory: true, size: total, itemCount: count,
                        modified: newest, children: children)
    }
}

/// Derived analyses over a completed scan tree.
nonisolated enum TreeAnalyzer {
    static let bundleSuffixes = [".app", ".photoslibrary", ".musiclibrary", ".tvlibrary", ".framework", ".xcarchive"]

    static func isInsideBundle(_ path: String) -> Bool {
        bundleSuffixes.contains { path.contains($0 + "/") }
    }

    /// node_modules and SwiftPM `.build` folders inside the user's projects.
    static func projectArtifacts(root: FileNode, home: String, minSize: Int64 = 10 << 20) -> [CleanupCandidate] {
        guard let homeNode = root.node(at: home) else { return [] }
        var result: [CleanupCandidate] = []

        func visit(_ node: FileNode) {
            for child in node.children where child.isDirectory {
                if node.path == home && child.name == "Library" { continue }
                if bundleSuffixes.contains(where: { child.name.hasSuffix($0) }) { continue }
                if child.name == "node_modules" {
                    if child.size >= minSize {
                        result.append(CleanupCandidate(
                            path: child.path, name: PathUtils.lastComponent(node.path),
                            detail: PathUtils.abbreviate(child.path, home: home), size: child.size,
                            lastModified: child.modified, safety: .caution, category: .packages,
                            ruleID: "packages.nodeModules", ruleName: "專案 node_modules",
                            note: "執行 npm / yarn install 即可重建"))
                    }
                    continue
                }
                if child.name == ".build" {
                    if child.size >= minSize && FileManager.default.fileExists(atPath: PathUtils.join(node.path, "Package.swift")) {
                        result.append(CleanupCandidate(
                            path: child.path, name: PathUtils.lastComponent(node.path),
                            detail: PathUtils.abbreviate(child.path, home: home), size: child.size,
                            lastModified: child.modified, safety: .safe, category: .packages,
                            ruleID: "packages.spmBuild", ruleName: "SwiftPM .build 資料夾",
                            note: "swift build 會自動重建"))
                    }
                    continue
                }
                if child.name.hasPrefix(".") { continue }
                visit(child)
            }
        }
        visit(homeNode)
        return result.sorted { $0.size > $1.size }
    }

    /// Files at or above `minSize`, skipping app/library bundles and protected system paths.
    static func largeFiles(root: FileNode, minSize: Int64, limit: Int = 500) -> [FileNode] {
        var result: [FileNode] = []
        func visit(_ node: FileNode) {
            for child in node.children where child.size >= minSize {
                if child.isDirectory {
                    if bundleSuffixes.contains(where: { child.name.hasSuffix($0) }) { continue }
                    visit(child)
                } else if !child.isAggregate && PathGuard.isDeletionAllowed(child.path) {
                    result.append(child)
                }
            }
        }
        visit(root)
        return Array(result.sorted { $0.size > $1.size }.prefix(limit))
    }

    static func search(root: FileNode, query: String, limit: Int = 300) -> [FileNode] {
        var result: [FileNode] = []
        func visit(_ node: FileNode) {
            for child in node.children where !child.isAggregate {
                if Task.isCancelled { return }
                if child.name.localizedCaseInsensitiveContains(query) { result.append(child) }
                if child.isDirectory { visit(child) }
            }
        }
        visit(root)
        return Array(result.sorted { $0.size > $1.size }.prefix(limit))
    }
}
