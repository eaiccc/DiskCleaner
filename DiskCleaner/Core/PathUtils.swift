//
//  PathUtils.swift
//  DiskCleaner
//
//  Formatting, path helpers and the S001 deletion guard.
//

import Foundation

nonisolated extension Int64 {
    func formattedSize() -> String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

nonisolated enum PathUtils {
    /// Real home directory (the app is not sandboxed).
    static var home: String { NSHomeDirectory() }

    /// `$TMPDIR` without trailing slash, e.g. `/var/folders/xx/yyyy/T`.
    static var tmpDir: String { trimTrailingSlash(NSTemporaryDirectory()) }

    static func join(_ parent: String, _ name: String) -> String {
        parent == "/" ? "/" + name : parent + "/" + name
    }

    static func trimTrailingSlash(_ path: String) -> String {
        var p = path
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }

    static func abbreviate(_ path: String, home: String = PathUtils.home) -> String {
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    static func lastComponent(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    static func parent(_ path: String) -> String {
        (path as NSString).deletingLastPathComponent
    }

    /// `true` when `path` equals `ancestor` or lives inside it.
    static func isSameOrInside(_ path: String, _ ancestor: String) -> Bool {
        if ancestor == "/" { return path.hasPrefix("/") }
        return path == ancestor || path.hasPrefix(ancestor + "/")
    }

    /// Expands `{a,b}` brace groups (non-nested) into every combination.
    static func expandBraces(_ pattern: String) -> [String] {
        guard let open = pattern.firstIndex(of: "{"),
              let close = pattern[open...].firstIndex(of: "}") else { return [pattern] }
        let prefix = String(pattern[..<open])
        let suffix = String(pattern[pattern.index(after: close)...])
        let options = pattern[pattern.index(after: open)..<close].split(separator: ",", omittingEmptySubsequences: false)
        return options.flatMap { expandBraces(prefix + $0 + suffix) }
    }
}

/// S001: system directory protection plus a list of critical folders that must never be removed as a whole.
nonisolated enum PathGuard {
    static let protectedRoots = ["/System", "/usr", "/bin", "/sbin", "/private", "/Library/Apple", "/dev"]

    /// Maps firmlinked aliases (`/tmp`, `/var`, `/etc`) onto `/private/...` and strips trailing slashes.
    static func normalize(_ path: String) -> String {
        var p = PathUtils.trimTrailingSlash(path)
        for alias in ["/tmp", "/var", "/etc"] where PathUtils.isSameOrInside(p, alias) {
            p = "/private" + p
            break
        }
        return p
    }

    static func criticalPaths(home: String) -> Set<String> {
        let h = normalize(home)
        var set: Set<String> = ["/", "/Applications", "/Library", "/Users", "/Volumes", "/opt", "/opt/homebrew", "/Library/Logs", h]
        let subs = ["Library", "Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music", "Public",
                    "Applications", ".Trash", "Library/Caches", "Library/Logs", "Library/Developer",
                    "Library/Developer/Xcode", "Library/Developer/CoreSimulator", "Library/Application Support",
                    "Library/Containers", "Library/Group Containers", "Library/Mobile Documents",
                    "Library/Developer/Xcode/DerivedData", "Library/Developer/Xcode/Archives",
                    "Library/Preferences", "Library/Keychains"]
        for s in subs { set.insert(h + "/" + s) }
        return set
    }

    static func isDeletionAllowed(_ path: String, home: String = PathUtils.home, tmpDir: String = PathUtils.tmpDir) -> Bool {
        let p = normalize(path)
        guard p.hasPrefix("/"), p.count > 1 else { return false }
        if p.split(separator: "/").contains(where: { $0 == ".." || $0 == "." }) { return false }
        if criticalPaths(home: home).contains(p) { return false }

        // Explicit exceptions inside /private: the user's own $TMPDIR and /tmp contents.
        for allowed in [normalize(tmpDir), "/private/tmp"] where p.hasPrefix(allowed + "/") {
            return true
        }
        for root in protectedRoots where PathUtils.isSameOrInside(p, root) {
            return false
        }
        return true
    }
}
