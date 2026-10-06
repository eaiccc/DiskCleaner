//
//  LargeFilesView.swift
//  DiskCleaner
//
//  Display top large files with size filtering and quick basket addition.
//

import SwiftUI
import AppKit

struct LargeFilesView: View {
    @Bindable var store = AppStore.shared

    @State private var searchText = ""
    @State private var minSizeMB: Double = 100

    var items: [FileNode] {
        let minBytes = Int64(minSizeMB * 1024 * 1024)
        return store.largeFiles.filter { node in
            node.size >= minBytes &&
            (searchText.isEmpty || node.name.localizedCaseInsensitiveContains(searchText) || node.path.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("大型檔案排行")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("找出散落硬碟各處的獨立大檔（影片、安裝映像檔、封裝模型）")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    let total = items.reduce(0) { $0 + $1.size }
                    Text("共 \(items.count) 個大檔 · \(total.formattedSize())")
                        .font(.system(size: 13, weight: .semibold))

                    Button("全部加入清理籃") {
                        let candidates = items.map { store.candidate(for: $0) }
                        store.addToBasket(candidates)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            // Filter bar
            HStack(spacing: 16) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜尋檔案名稱或路徑...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)

                HStack(spacing: 8) {
                    Text("門檻: \(Int(minSizeMB)) MB")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Slider(value: $minSizeMB, in: 50...1000, step: 50)
                        .frame(width: 120)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            Divider()

            if items.isEmpty {
                VStack(spacing: 12) {
                    if store.isTreeScanning {
                        ProgressView()
                            .controlSize(.large)
                        Text("正在掃描磁碟尋找大檔案...")
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "archivebox")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("未發現大於 \(Int(minSizeMB)) MB 的大檔案")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(items) { node in
                    let candidate = store.candidate(for: node)
                    let inBasket = store.isInBasket(candidate)

                    HStack(spacing: 12) {
                        Toggle("", isOn: Binding(
                            get: { inBasket },
                            set: { store.setInBasket(candidate, $0) }
                        ))
                        .toggleStyle(.checkbox)

                        Image(systemName: fileIcon(node.name))
                            .font(.title3)
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(node.name)
                                    .font(.system(size: 13, weight: .medium))
                                SafetyBadge(safety: candidate.safety)
                            }
                            Text(PathUtils.abbreviate(node.path))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 3) {
                            Text(node.size.formattedSize())
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                            if let mod = node.modified {
                                Text(mod.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .contextMenu {
                        Button("在 Finder 中顯示") {
                            NSWorkspace.shared.selectFile(node.path, inFileViewerRootedAtPath: "")
                        }
                        Button(inBasket ? "從清理籃移除" : "加入清理籃") {
                            store.setInBasket(candidate, !inBasket)
                        }
                        Divider()
                        Button("排除此路徑") {
                            store.exclude(node.path)
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }

    private func fileIcon(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "mov", "mp4", "mkv", "avi": return "film"
        case "zip", "tar", "gz", "7z", "rar": return "doc.zipper"
        case "dmg", "iso", "img": return "opticaldisc"
        case "ipa", "app": return "app.badge"
        case "bin", "safetensors", "gguf", "pt", "onnx": return "brain"
        default: return "doc.fill"
        }
    }
}
