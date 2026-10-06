//
//  SystemServices.swift
//  DiskCleaner
//
//  Volume capacity, Full Disk Access detection, running-app checks and scan snapshots.
//

import Foundation
import AppKit

nonisolated struct DiskInfo: Sendable {
    var name: String = "Macintosh HD"
    var total: Int64 = 0
    /// Free space including purgeable data (what Finder reports as "available").
    var available: Int64 = 0
    /// Space that is free right now, excluding purgeable data.
    var availableNow: Int64 = 0

    var used: Int64 { max(0, total - available) }
    var usageRatio: Double { total > 0 ? Double(used) / Double(total) : 0 }

    static func read(path: String = PathUtils.home) -> DiskInfo {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
                                         .volumeAvailableCapacityKey, .volumeLocalizedNameKey]
        guard let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: keys) else { return DiskInfo() }
        let now = Int64(values.volumeAvailableCapacity ?? 0)
        return DiskInfo(name: values.volumeLocalizedName ?? "Macintosh HD",
                        total: Int64(values.volumeTotalCapacity ?? 0),
                        available: values.volumeAvailableCapacityForImportantUsage ?? now,
                        availableNow: now)
    }
}

nonisolated enum FullDiskAccess {
    /// Files only readable with Full Disk Access. If any of them can be opened, access is granted.
    static func isGranted(home: String = PathUtils.home) -> Bool {
        let probes = [
            "\(home)/Library/Application Support/com.apple.TCC/TCC.db",
            "/Library/Application Support/com.apple.TCC/TCC.db",
            "\(home)/Library/Safari/Bookmarks.plist"
        ]
        for path in probes {
            if let handle = FileHandle(forReadingAtPath: path) {
                try? handle.close()
                return true
            }
        }
        return false
    }

    @MainActor
    static func openSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }
}

enum RunningApps {
    /// Localized names of running apps among `bundleIDs`.
    static func names(for bundleIDs: Set<String>) -> [String] {
        guard !bundleIDs.isEmpty else { return [] }
        let names = NSWorkspace.shared.runningApplications
            .filter { bundleIDs.contains($0.bundleIdentifier ?? "") }
            .compactMap(\.localizedName)
        return Array(Set(names)).sorted()
    }
}

nonisolated enum SnapshotStore {
    struct Snapshot: Codable, Sendable {
        let date: Date
        let root: FileNode
    }

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("DiskCleaner", isDirectory: true)
    }

    static var fileURL: URL { directory.appendingPathComponent("scan-snapshot.json") }

    static func save(_ root: FileNode, date: Date) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Snapshot(date: date, root: root.pruned(minSize: 10 << 20)))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("SnapshotStore [ERROR]: save failed: \(error)")
        }
    }

    static func load() -> Snapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }
}
