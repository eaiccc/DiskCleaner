//
//  CleanupSheets.swift
//  DiskCleaner
//
//  Persistent basket bar and cleanup modal sheets (Confirmation, Progress, Report).
//

import SwiftUI

// MARK: - Persistent Basket Bar

struct BasketBar: View {
    @Bindable var store = AppStore.shared

    var body: some View {
        let items = store.basketItems
        if !items.isEmpty {
            let total = CleanupPlanner.totalSize(items)
            let safeSize = items.filter { $0.safety == .safe }.reduce(0) { $0 + $1.size }

            HStack(spacing: 16) {
                Image(systemName: "trash.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("已選 \(items.count) 個項目")
                            .font(.system(size: 13, weight: .bold))
                        Text("· 預計釋放 \(total.formattedSize())")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.blue)
                    }
                    if safeSize > 0 && safeSize < total {
                        Text("（其中 \(safeSize.formattedSize()) 為直接刪除的安全快取）")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button("清空清理籃") {
                    store.clearBasket()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.secondary)

                Button {
                    store.beginCleanup(items)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                        Text("開始清理")
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color.secondary.opacity(0.2)),
                alignment: .top
            )
        }
    }
}

// MARK: - Confirmation Sheet

struct CleanupConfirmationSheet: View {
    @Bindable var store = AppStore.shared

    var body: some View {
        let items = store.pendingItems
        let total = CleanupPlanner.totalSize(items)
        let reviewItems = items.filter { $0.safety == .review }

        VStack(spacing: 20) {
            // Header
            VStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.orange)
                Text("確認執行清理？")
                    .font(.title2.bold())
                Text("即將清理 \(items.count) 個項目，預計釋放 \(total.formattedSize()) 空間。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Running App Warnings
            if !store.runningAppWarnings.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "app.badge.checkmark")
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("以下相關應用程式正在執行中：")
                            .font(.caption.bold())
                        Text(store.runningAppWarnings.joined(separator: "、"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("建議先關閉應用程式，避免快取檔案被佔用或建置中斷。")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    Spacer()
                }
                .padding(10)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(8)
            }

            // Review Items Warning
            if !reviewItems.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "hand.raised.fill")
                        .foregroundColor(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("包含 \(reviewItems.count) 個謹慎項目（如 Archives、iOS 備份）：")
                            .font(.caption.bold())
                            .foregroundColor(.red)
                        Text("這些項目將移至「垃圾桶」，在清空前可於歷史紀錄放回原處。")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(10)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }

            // Items Preview List
            List(items.prefix(15)) { item in
                HStack {
                    SafetyBadge(safety: item.safety)
                    Text(item.name)
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(item.size.formattedSize())
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 180)
            .listStyle(.inset)
            .border(Color.secondary.opacity(0.15))

            if items.count > 15 {
                Text("以及其他 \(items.count - 15) 個項目...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Buttons
            HStack(spacing: 16) {
                Button("取消") {
                    store.cancelConfirmation()
                }
                .keyboardShortcut(.cancelAction)

                Button("確認執行清理") {
                    store.performCleanup()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}

// MARK: - Progress Sheet

struct CleanupProgressSheet: View {
    @Bindable var store = AppStore.shared

    var body: some View {
        VStack(spacing: 20) {
            Text("正在清理檔案...")
                .font(.headline)

            ProgressView(value: store.cleanupProgress, total: 1.0)
                .progressViewStyle(.linear)
                .frame(width: 320)

            HStack {
                Text("\(Int(store.cleanupProgress * 100))%")
                    .font(.caption.bold())
                Spacer()
                Text(store.cleanupCurrent)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 240)
            }
            .frame(width: 320)

            Button("取消清理") {
                store.cancelCleanup()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(32)
        .frame(width: 420)
    }
}

// MARK: - Report Sheet

struct CleanupReportSheet: View {
    @Bindable var store = AppStore.shared

    var body: some View {
        if let report = store.report {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.green)

                Text("清理完成！")
                    .font(.title2.bold())

                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Text("實際釋放硬碟空間：")
                            .foregroundColor(.secondary)
                        Text(report.actualFreed.formattedSize())
                            .font(.title3.bold())
                            .foregroundColor(.green)
                    }

                    Text("成功處理 \(report.result.done.count) 個項目")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if report.trashedSize > 0 {
                        HStack(spacing: 6) {
                            Text("其中 \(report.trashedSize.formattedSize()) 已移入垃圾桶。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Button("立即永久刪除") {
                                store.purgeTrashedItemsOfLastReport()
                            }
                            .font(.caption)
                            .buttonStyle(.link)
                        }
                    }

                    if !report.result.failed.isEmpty {
                        Text("\(report.result.failed.count) 個項目處理失敗（可能是系統使用中）")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Button("完成") {
                    store.dismissCleanup()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(32)
            .frame(width: 440)
        }
    }
}
