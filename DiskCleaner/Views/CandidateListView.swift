//
//  CandidateListView.swift
//  DiskCleaner
//
//  Reusable list for categorized candidate items (Xcode, Simulators, AI, Temp, Packages).
//

import SwiftUI
import AppKit

struct CandidateListView: View {
    let categories: Set<CleanupCategory>
    let title: String
    let subtitle: String

    @Bindable var store = AppStore.shared

    @State private var searchText = ""
    @State private var filterSafety: Safety? = nil

    var items: [CleanupCandidate] {
        store.candidates.filter { categories.contains($0.category) }
    }

    var filteredItems: [CleanupCandidate] {
        items.filter { item in
            let matchQuery = searchText.isEmpty ||
                item.name.localizedCaseInsensitiveContains(searchText) ||
                item.detail.localizedCaseInsensitiveContains(searchText) ||
                item.ruleName.localizedCaseInsensitiveContains(searchText)
            let matchSafety = filterSafety == nil || item.safety == filterSafety
            return matchQuery && matchSafety
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()

                // Actions
                VStack(alignment: .trailing, spacing: 6) {
                    let totalSize = items.reduce(0) { $0 + $1.size }
                    let safeSize = items.filter { $0.safety == .safe }.reduce(0) { $0 + $1.size }

                    HStack(spacing: 12) {
                        Text("共 \(items.count) 項 · \(totalSize.formattedSize())")
                            .font(.system(size: 13, weight: .semibold))
                        if safeSize > 0 {
                            Text("（安全可清 \(safeSize.formattedSize())）")
                                .font(.system(size: 12))
                                .foregroundColor(.green)
                        }
                    }

                    HStack(spacing: 8) {
                        Button("全選安全項目") {
                            let safes = items.filter { $0.safety == .safe }
                            store.addToBasket(safes)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("全部加入清理籃") {
                            store.addToBasket(items)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("取消本頁選取") {
                            store.removeFromBasket(items)
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            // Search and filter toolbar
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜尋名稱、規則或路徑...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)

                Picker("安全等級", selection: $filterSafety) {
                    Text("全部等級").tag(Safety?.none)
                    Text("🟢 安全").tag(Safety?.some(.safe))
                    Text("🟡 注意").tag(Safety?.some(.caution))
                    Text("🔴 謹慎").tag(Safety?.some(.review))
                }
                .pickerStyle(.menu)
                .frame(width: 120)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            Divider()

            if items.isEmpty {
                VStack(spacing: 12) {
                    if store.isScanning {
                        ProgressView()
                            .controlSize(.large)
                        Text("正在掃描 \(title)...")
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.green)
                        Text("太棒了！沒有發現可清理項目")
                            .font(.headline)
                        Text("此類別目前沒有快取或暫存佔用空間。")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredItems) { item in
                    let inBasket = store.isInBasket(item)
                    HStack(spacing: 12) {
                        Toggle("", isOn: Binding(
                            get: { inBasket },
                            set: { store.setInBasket(item, $0) }
                        ))
                        .toggleStyle(.checkbox)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(item.name)
                                    .font(.system(size: 13, weight: .medium))
                                SafetyBadge(safety: item.safety)
                                Text(item.ruleName)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Text(item.detail)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 3) {
                            Text(item.size.formattedSize())
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                            Text(item.action.label)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .contextMenu {
                        if item.hasFilesystemPath {
                            Button("在 Finder 中顯示") {
                                NSWorkspace.shared.selectFile(item.path, inFileViewerRootedAtPath: "")
                            }
                        }
                        Button(inBasket ? "從清理籃移除" : "加入清理籃") {
                            store.setInBasket(item, !inBasket)
                        }
                        if let note = item.note {
                            Divider()
                            Text(note).foregroundColor(.secondary)
                        }
                        if item.hasFilesystemPath {
                            Divider()
                            Button("排除此路徑") {
                                store.exclude(item.path)
                            }
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }
}
