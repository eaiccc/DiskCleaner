//
//  CleanupRecord.swift
//  DiskCleaner
//
//  Created by Link on 2026/6/3.
//

import Foundation
import SwiftData

/// One cleaned item. Items moved to the Trash keep `trashPath` so they can be put back.
@Model
final class CleanupRecord {
    @Attribute(.unique) var id: UUID
    var batchID: UUID
    var timestamp: Date
    var name: String
    var originalPath: String
    var trashPath: String?
    var fileSize: Int64
    var category: String
    var safety: String
    /// "delete" / "trash" / "simctl"
    var actionKind: String
    var restored: Bool

    init(id: UUID = UUID(), batchID: UUID, timestamp: Date = Date(), name: String, originalPath: String,
         trashPath: String?, fileSize: Int64, category: String, safety: String, actionKind: String) {
        self.id = id
        self.batchID = batchID
        self.timestamp = timestamp
        self.name = name
        self.originalPath = originalPath
        self.trashPath = trashPath
        self.fileSize = fileSize
        self.category = category
        self.safety = safety
        self.actionKind = actionKind
        self.restored = false
    }

    var canRestore: Bool {
        guard actionKind == "trash", !restored, let trashPath else { return false }
        return FileManager.default.fileExists(atPath: trashPath)
    }
}
