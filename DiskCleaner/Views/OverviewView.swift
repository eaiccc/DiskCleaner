//
//  OverviewView.swift
//  DiskCleaner
//
//  Dashboard overview: disk capacity ring, one-click safe clean, category summary cards.
//

import SwiftUI

struct OverviewView: View {
    @Bindable var store = AppStore.shared
    let onNavigate: (SidebarSection) -> Void

    @State private var isGaugeScanning = false
    @State private var isGaugePulse = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // FDA Banner
                FDABanner()

                // Low space alert
                if store.isLowSpace {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.white)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("硬碟空間嚴重不足！")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("可用空間已低於 10%，可能影響 macOS 虛擬記憶體與 Xcode 建置效能。")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.9))
                        }
                        Spacer()
                    }
                    .padding(16)
                    .background(Color.red.opacity(0.85))
                    .cornerRadius(12)
                    .padding(.horizontal, 24)
                }

                // Live Scanning Animation Card
                if store.isScanning {
                    DiskScanningCardView()
                }

                // Storage Capacity Card
                storageCard

                // Category Summary Grid
                categoryGrid
            }
            .padding(.vertical, 24)
        }
        .onAppear {
            withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                isGaugeScanning = true
            }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                isGaugePulse = true
            }
        }
    }

    // MARK: - Storage Card

    private var storageCard: some View {
        let disk = store.disk
        let safeItems = store.safeCandidates
        let safeSize = safeItems.reduce(0) { $0 + $1.size }

        return VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 24) {
                // Circular Gauge
                ZStack {
                    // Scanning outer aura ring
                    if store.isScanning {
                        Circle()
                            .stroke(
                                AngularGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: .clear, location: 0.0),
                                        .init(color: .cyan.opacity(0.2), location: 0.5),
                                        .init(color: .cyan, location: 1.0)
                                    ]),
                                    center: .center
                                ),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round)
                            )
                            .frame(width: 132, height: 132)
                            .rotationEffect(.degrees(isGaugeScanning ? 360 : 0))
                            .shadow(color: .cyan.opacity(0.6), radius: 6)

                        Circle()
                            .stroke(Color.cyan.opacity(0.3), lineWidth: 1.2)
                            .frame(width: 140, height: 140)
                            .scaleEffect(isGaugePulse ? 1.08 : 0.94)
                            .opacity(isGaugePulse ? 0 : 0.7)
                    }

                    Circle()
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 14)
                        .frame(width: 110, height: 110)

                    Circle()
                        .trim(from: 0, to: CGFloat(disk.usageRatio))
                        .stroke(
                            AngularGradient(gradient: Gradient(colors: [.blue, .purple, .pink]), center: .center),
                            style: StrokeStyle(lineWidth: 14, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 110, height: 110)

                    VStack(spacing: 2) {
                        Text("\(Int(disk.usageRatio * 100))%")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        if store.isScanning {
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 5, height: 5)
                                Text("掃描中")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.cyan)
                            }
                        } else {
                            Text("已使用")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Details
                VStack(alignment: .leading, spacing: 8) {
                    Text(disk.name)
                        .font(.title2.bold())

                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("已用空間")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(disk.used.formattedSize())
                                .font(.headline)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("可用空間")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(disk.available.formattedSize())
                                .font(.headline)
                                .foregroundColor(.green)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("總容量")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(disk.total.formattedSize())
                                .font(.headline)
                        }
                    }

                    if safeSize > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .foregroundColor(.green)
                            Text("可立即安全釋放約 \(safeSize.formattedSize()) 空間")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.green)
                        }
                    }
                }

                Spacer()

                // Quick Action Button
                VStack(spacing: 8) {
                    Button {
                        store.beginCleanup(safeItems)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                            Text("一鍵清理安全項目")
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .controlSize(.large)
                    .disabled(safeItems.isEmpty)

                    if safeSize > 0 {
                        Text("預計釋放 \(safeSize.formattedSize())")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(24)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Category Grid

    private var categoryGrid: some View {
        let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

        return LazyVGrid(columns: columns, spacing: 16) {
            categoryCard(title: "Xcode 開發檔案",
                         icon: "hammer.fill",
                         color: .blue,
                         section: .xcode,
                         category: [.xcode],
                         detail: "DerivedData、Previews、DeviceSupport")

            categoryCard(title: "模擬器與裝置",
                         icon: "iphone",
                         color: .indigo,
                         section: .simulator,
                         category: [.simulator],
                         detail: "不可用裝置、舊版 Runtime、測試快照")

            categoryCard(title: "AI 工具快取",
                         icon: "brain.head.profile",
                         color: .purple,
                         section: .ai,
                         category: [.ai],
                         detail: "HuggingFace、Ollama、LM Studio、Cursor")

            categoryCard(title: "暫存檔與系統 Log",
                         icon: "doc.text.fill",
                         color: .teal,
                         section: .tempLogs,
                         category: [.tempLogs],
                         detail: "$TMPDIR、/tmp、當機診斷報告")

            categoryCard(title: "專案與套件快取",
                         icon: "shippingbox.fill",
                         color: .orange,
                         section: .packages,
                         category: [.packages],
                         detail: "SwiftPM、CocoaPods、npm、node_modules")

            categoryCard(title: "大型檔案排行",
                         icon: "archivebox.fill",
                         color: .red,
                         section: .largeFiles,
                         category: [.largeFiles],
                         detail: "超過 100MB 獨立大檔案清單")
        }
        .padding(.horizontal, 24)
    }

    private func categoryCard(title: String, icon: String, color: Color,
                              section: SidebarSection, category: Set<CleanupCategory>, detail: String) -> some View {
        let summary = store.summary(for: category)

        return Button {
            onNavigate(section)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundColor(color)
                        .frame(width: 32, height: 32)
                        .background(color.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.primary)
                        Text(detail)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.total > 0 ? summary.total.formattedSize() : "0 KB")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        Text("\(summary.count) 項可整理")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if summary.safeTotal > 0 {
                        Text("安全可清 \(summary.safeTotal.formattedSize())")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}
