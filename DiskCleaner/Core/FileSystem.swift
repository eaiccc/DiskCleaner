//
//  FileSystem.swift
//  DiskCleaner
//
//  Low-level POSIX directory listing and recursive measuring.
//

import Foundation

nonisolated struct DirEntry: Sendable {
    let name: String
    let path: String
    let isDirectory: Bool
    /// Allocated bytes on disk (st_blocks * 512), so sparse / dataless files are counted correctly.
    let allocated: Int64
    let linkCount: UInt16
    let device: Int32
    let inode: UInt64
    let modified: Date
}

nonisolated struct Measurement: Sendable {
    var size: Int64 = 0
    var newest: Date? = nil
    var fileCount: Int = 0
}

nonisolated enum FS {
    private static func makeEntry(name: String, path: String, _ st: stat) -> DirEntry {
        DirEntry(
            name: name,
            path: path,
            isDirectory: (st.st_mode & S_IFMT) == S_IFDIR,
            allocated: Int64(st.st_blocks) * 512,
            linkCount: st.st_nlink,
            device: st.st_dev,
            inode: st.st_ino,
            modified: Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
        )
    }

    /// `lstat` a single path (symlinks are not followed).
    static func entry(at path: String) -> DirEntry? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        return makeEntry(name: PathUtils.lastComponent(path), path: path, st)
    }

    /// Lists a directory with `readdir` + `fstatat`. Returns nil when the directory cannot be opened.
    static func list(_ path: String) -> [DirEntry]? {
        guard let dir = opendir(path) else { return nil }
        defer { closedir(dir) }
        let fd = dirfd(dir)
        var entries: [DirEntry] = []
        while let ent = readdir(dir) {
            let length = Int(ent.pointee.d_namlen)
            let name: String = withUnsafePointer(to: ent.pointee.d_name) { tuplePtr in
                tuplePtr.withMemoryRebound(to: CChar.self, capacity: length + 1) { cName in
                    FileManager.default.string(withFileSystemRepresentation: cName, length: length)
                }
            }
            if name == "." || name == ".." { continue }
            var st = stat()
            guard fstatat(fd, name, &st, AT_SYMLINK_NOFOLLOW) == 0 else { continue }
            entries.append(makeEntry(name: name, path: PathUtils.join(path, name), st))
        }
        return entries
    }

    /// Total allocated size, newest modification date (files and folders) and file count.
    static func measure(_ path: String) -> Measurement {
        guard let top = entry(at: path) else { return Measurement() }
        var m = Measurement(size: top.allocated, newest: top.modified, fileCount: top.isDirectory ? 0 : 1)
        guard top.isDirectory else { return m }
        var stack = [path]
        while let dir = stack.popLast() {
            if Task.isCancelled { break }
            guard let children = list(dir) else { continue }
            for e in children {
                m.size += e.allocated
                if let newest = m.newest, e.modified > newest { m.newest = e.modified }
                if e.isDirectory { stack.append(e.path) } else { m.fileCount += 1 }
            }
        }
        return m
    }
}
