//
//  HistoryView.swift
//  DiskCleaner
//
//  Cleanup history log with one-click restoration for items moved to Trash.
//

import SwiftUI
import SwiftData
import AppKit

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CleanupRecord.timestamp, order: .reverse) private var records: [CleanupRecord]
    @Bindable var store = AppStore.shared

    @State private var restoreError: String? = nil
    @State private var showingErrorAlert = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("清理歷史與復原")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("移入垃圾桶的項目可在尚未清空垃圾桶前放回原處")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()

                Button("清除 30 天前紀錄") {
                    store.purgeOldRecords(olderThanDays: 30)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            if records.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 56))
                        .foregroundColor(.secondary)
                    Text("尚無清理紀錄")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("每次執行清理後，紀錄會保存在此處以供查詢與復原。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(records) { record in
                    HStack(spacing: 12) {
                        Image(systemName: iconFor(record.actionKind))
                            .foregroundColor(colorFor(record.actionKind))
                            .font(.title3)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(record.name)
                                    .font(.system(size: 13, weight: .medium))
                                Text(record.category)
                                    .font(.system(size: 11))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.12))
                                    .cornerRadius(4)
                                if record.restored {
                                    Text("已復原")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                }
                            }
                            Text(PathUtils.abbreviate(record.originalPath))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text(record.fileSize.formattedSize())
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                            Text(record.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        if record.canRestore {
                            Button("放回原處") {
                                if let err = store.restore(record) {
                                    restoreError = err
                                    showingErrorAlert = true
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .alert("復原失敗", isPresented: $showingErrorAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text(restoreError ?? "未知錯誤")
        }
    }

    private func iconFor(_ action: String) -> String {
        switch action {
        case "trash": return "trash.fill"
        case "delete": return "xmark.bin.fill"
        case "simctl": return "iphone.slash"
        default: return "doc.fill"
        }
    }

    private func colorFor(_ action: String) -> Color {
        switch action {
        case "trash": return .orange
        case "delete": return .red
        case "simctl": return .blue
        default: return .secondary
        }
    }
}
