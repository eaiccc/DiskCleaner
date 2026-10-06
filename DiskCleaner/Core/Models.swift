//
//  Models.swift
//  DiskCleaner
//
//  Core value types shared by the scanner, rule engine, executor and UI.
//

import Foundation

/// How risky it is to remove an item. Drives the default cleanup action (see plan "決策 2").
nonisolated enum Safety: String, Codable, CaseIterable, Sendable, Comparable {
    case safe, caution, review

    var rank: Int {
        switch self {
        case .safe: return 0
        case .caution: return 1
        case .review: return 2
        }
    }

    static func < (lhs: Safety, rhs: Safety) -> Bool { lhs.rank < rhs.rank }

    var label: String {
        switch self {
        case .safe: return "安全"
        case .caution: return "注意"
        case .review: return "謹慎"
        }
    }

    var explanation: String {
        switch self {
        case .safe: return "可自動重建，直接刪除"
        case .caution: return "需重新下載或重建，移到垃圾桶"
        case .review: return "可能是重要資料，移到垃圾桶並需再次確認"
        }
    }

    /// Safe items are deleted outright (moving to Trash frees no space); the rest go to the Trash.
    var defaultAction: CleanupAction { self == .safe ? .delete : .trash }
}

nonisolated enum CleanupCategory: String, Codable, CaseIterable, Sendable {
    case xcode, simulator, packages, ai, tempLogs, backups, largeFiles, custom

    var title: String {
        switch self {
        case .xcode: return "Xcode"
        case .simulator: return "模擬器"
        case .packages: return "套件快取"
        case .ai: return "AI 工具"
        case .tempLogs: return "暫存、快取與 Log"
        case .backups: return "裝置備份"
        case .largeFiles: return "大型檔案"
        case .custom: return "自選項目"
        }
    }

    var icon: String {
        switch self {
        case .xcode: return "hammer.fill"
        case .simulator: return "iphone"
        case .packages: return "shippingbox.fill"
        case .ai: return "brain.head.profile"
        case .tempLogs: return "doc.text.fill"
        case .backups: return "externaldrive.fill.badge.timemachine"
        case .largeFiles: return "archivebox.fill"
        case .custom: return "folder.fill"
        }
    }
}

nonisolated enum CleanupAction: Hashable, Sendable {
    case delete
    case trash
    case simctlDeleteDevice(udid: String)
    case simctlDeleteRuntime(identifier: String)

    var label: String {
        switch self {
        case .delete: return "直接刪除"
        case .trash: return "移到垃圾桶"
        case .simctlDeleteDevice: return "simctl 刪除裝置"
        case .simctlDeleteRuntime: return "simctl 刪除 Runtime"
        }
    }

    /// Short key persisted in `CleanupRecord.actionKind`.
    var kind: String {
        switch self {
        case .delete: return "delete"
        case .trash: return "trash"
        case .simctlDeleteDevice, .simctlDeleteRuntime: return "simctl"
        }
    }
}

/// A declarative cleanup rule loaded from `rules.json`.
nonisolated struct CleanupRule: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let category: CleanupCategory
    let safety: Safety
    /// Glob patterns. Supports `~`, `$TMPDIR` and `{a,b}` brace groups.
    let paths: [String]
    /// Only include matches whose newest content is older than N days.
    var minAgeDays: Int? = nil
    /// Bundle identifiers that should be quit before cleaning.
    var runningApps: [String]? = nil
    var note: String? = nil
    /// derivedData / archive / huggingface / parentAndLast / iosBackup
    var nameStyle: String? = nil
    /// Used only for tagging paths in Space Explorer, never produces candidates.
    var classifyOnly: Bool? = nil
}

nonisolated struct RuleFile: Codable, Sendable {
    let version: Int
    let rules: [CleanupRule]
}

/// Something the user can clean. Produced by rules, `simctl`, tree analysis or manual selection.
nonisolated struct CleanupCandidate: Identifiable, Hashable, Sendable {
    let id: String
    let path: String
    let name: String
    let detail: String
    let size: Int64
    let lastModified: Date?
    let safety: Safety
    let category: CleanupCategory
    let ruleID: String
    let ruleName: String
    let note: String?
    let action: CleanupAction
    let runningApps: [String]

    init(id: String? = nil, path: String, name: String, detail: String, size: Int64,
         lastModified: Date?, safety: Safety, category: CleanupCategory,
         ruleID: String, ruleName: String, note: String? = nil,
         action: CleanupAction? = nil, runningApps: [String] = []) {
        self.id = id ?? path
        self.path = path
        self.name = name
        self.detail = detail
        self.size = size
        self.lastModified = lastModified
        self.safety = safety
        self.category = category
        self.ruleID = ruleID
        self.ruleName = ruleName
        self.note = note
        self.action = action ?? safety.defaultAction
        self.runningApps = runningApps
    }

    /// Whether this candidate occupies a real filesystem path (used for nested de-duplication).
    var hasFilesystemPath: Bool { path.hasPrefix("/") }
}
