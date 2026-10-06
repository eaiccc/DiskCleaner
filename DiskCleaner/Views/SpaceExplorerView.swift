//
//  SpaceExplorerView.swift
//  DiskCleaner
//
//  Breadcrumb navigation, hierarchical outline list and interactive treemap.
//

import SwiftUI
import AppKit

struct SpaceExplorerView: View {
    @Bindable var store = AppStore.shared

    @State private var currentPath: String = "/"
    @State private var selectedNodeID: String? = nil
    @State private var searchText: String = ""

    var currentNode: FileNode? {
        guard let root = store.root else { return nil }
        return root.node(at: currentPath) ?? root
    }

    var body: some View {
        VStack(spacing: 0) {
            // Breadcrumbs bar
            breadcrumbBar

            Divider()

            if let node = currentNode {
                HSplitView {
                    // Left: File list
                    fileListView(node: node)
                        .frame(minWidth: 380, idealWidth: 460)

                    // Right: Treemap
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("容量視覺化分佈")
                                .font(.headline)
                            Spacer()
                            Text("點選方塊進入子目錄")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                        TreemapView(node: node) { child in
                            currentPath = child.path
                        }
                        .padding(12)
                    }
                    .frame(minWidth: 300)
                }
            } else if store.isTreeScanning {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                    Text("正在掃描檔案結構...")
                        .font(.headline)
                    Text(store.currentPath)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 400)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "internaldrive.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Text("尚未掃描磁碟")
                        .font(.headline)
                    Button("立即開始全碟掃描") {
                        store.startScan()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Breadcrumb

    private var breadcrumbBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "internaldrive")
                .foregroundColor(.secondary)

            let segments = makeSegments(path: currentPath)
            ForEach(segments.indices, id: \.self) { idx in
                let seg = segments[idx]
                if idx > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Button {
                    currentPath = seg.path
                } label: {
                    Text(seg.title)
                        .font(.system(size: 12, weight: idx == segments.count - 1 ? .bold : .regular))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if currentPath != "/" {
                Button {
                    currentPath = PathUtils.parent(currentPath)
                } label: {
                    Label("上一層", systemImage: "arrow.up")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Search in folder
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜尋...", text: $searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 140)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private struct Segment { let title: String; let path: String }
    private func makeSegments(path: String) -> [Segment] {
        if path == "/" { return [Segment(title: store.disk.name, path: "/")] }
        var list: [Segment] = [Segment(title: store.disk.name, path: "/")]
        var build = ""
        let parts = path.split(separator: "/")
        for part in parts {
            build += "/" + part
            list.append(Segment(title: String(part), path: build))
        }
        return list
    }

    // MARK: - List View

    private func fileListView(node: FileNode) -> some View {
        let displayNodes = node.children
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.size > $1.size }

        let maxSize = displayNodes.first?.size ?? 1

        return List(displayNodes, selection: $selectedNodeID) { child in
            HStack(spacing: 10) {
                // Icon
                Image(systemName: child.isDirectory ? "folder.fill" : "doc.fill")
                    .foregroundColor(child.isDirectory ? .blue : .secondary)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(child.name)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)

                        if let rule = store.classify(child.path) {
                            SafetyBadge(safety: rule.safety)
                        }
                    }

                    if let mod = child.modified {
                        Text("修改於 " + mod.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(child.size.formattedSize())
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    SizeBar(value: child.size, max: maxSize)
                        .frame(width: 70)
                }

                if child.isDirectory && !child.children.isEmpty {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                if child.isDirectory && !child.children.isEmpty {
                    currentPath = child.path
                }
            }
            .contextMenu {
                Button("在 Finder 中顯示") {
                    NSWorkspace.shared.selectFile(child.path, inFileViewerRootedAtPath: "")
                }
                Button("加入清理籃") {
                    let candidate = store.candidate(for: child)
                    store.setInBasket(candidate, true)
                }
                Divider()
                Button("排除此路徑") {
                    store.exclude(child.path)
                }
                Button("複製路徑") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(child.path, forType: .string)
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }
}
