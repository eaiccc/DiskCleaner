//
//  TreemapView.swift
//  DiskCleaner
//
//  Interactive squarified treemap rendering FileNode hierarchy.
//

import SwiftUI

struct TreemapItem: Identifiable {
    let node: FileNode
    let rect: CGRect
    let color: Color
    var id: String { node.path }
}

enum TreemapLayout {
    static let palette: [Color] = [
        .blue, .indigo, .purple, .pink, .orange, .teal, .green, .cyan, .mint
    ]

    static func layout(nodes: [FileNode], in bounds: CGRect) -> [TreemapItem] {
        guard !nodes.isEmpty, bounds.width > 0, bounds.height > 0 else { return [] }
        let total = nodes.reduce(0) { $0 + $1.size }
        guard total > 0 else { return [] }

        var items: [TreemapItem] = []
        var remaining = bounds

        // Simple slice-and-dice / alternating strip layout for responsiveness
        for (index, node) in nodes.enumerated() {
            guard node.size > 0 else { continue }
            let fraction = CGFloat(Double(node.size) / Double(total))
            let color = palette[index % palette.count]

            if remaining.width >= remaining.height {
                let w = index == nodes.count - 1 ? remaining.width : remaining.width * fraction
                let itemRect = CGRect(x: remaining.minX, y: remaining.minY, width: w, height: remaining.height)
                items.append(TreemapItem(node: node, rect: itemRect, color: color))
                remaining = CGRect(x: remaining.minX + w, y: remaining.minY, width: Swift.max(0, remaining.width - w), height: remaining.height)
            } else {
                let h = index == nodes.count - 1 ? remaining.height : remaining.height * fraction
                let itemRect = CGRect(x: remaining.minX, y: remaining.minY, width: remaining.width, height: h)
                items.append(TreemapItem(node: node, rect: itemRect, color: color))
                remaining = CGRect(x: remaining.minX, y: remaining.minY + h, width: remaining.width, height: Swift.max(0, remaining.height - h))
            }
        }
        return items
    }
}

struct TreemapView: View {
    let node: FileNode
    let onSelect: (FileNode) -> Void

    @State private var hoveredID: String? = nil

    var body: some View {
        GeometryReader { geo in
            let displayChildren = node.children.filter { $0.size > 0 }
            let items = TreemapLayout.layout(nodes: displayChildren, in: CGRect(origin: .zero, size: geo.size))

            ZStack(alignment: .topLeading) {
                if items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "square.dashed")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("無子項目或目錄為空")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ForEach(items) { item in
                        let isHovered = hoveredID == item.id
                        ZStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(item.color.opacity(isHovered ? 0.85 : 0.65))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(isHovered ? Color.white : Color.black.opacity(0.2), lineWidth: isHovered ? 2 : 1)
                                )

                            if item.rect.width > 50 && item.rect.height > 30 {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.node.name)
                                        .font(.system(size: 11, weight: .bold))
                                        .lineLimit(1)
                                        .foregroundColor(.white)
                                    Text(item.node.size.formattedSize())
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.9))
                                }
                                .padding(4)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            }
                        }
                        .frame(width: Swift.max(1, item.rect.width - 2), height: Swift.max(1, item.rect.height - 2))
                        .position(x: item.rect.midX, y: item.rect.midY)
                        .contentShape(Rectangle())
                        .onHover { isHovering in
                            hoveredID = isHovering ? item.id : nil
                        }
                        .onTapGesture {
                            if item.node.isDirectory && !item.node.children.isEmpty {
                                onSelect(item.node)
                            }
                        }
                        .help("\(item.node.name)\n大小：\(item.node.size.formattedSize())\n點擊進入資料夾")
                    }
                }
            }
        }
    }
}
