//
//  DiskScanningView.swift
//  DiskCleaner
//
//  Dedicated loading & radar scanning animation components for disk scan operations.
//

import SwiftUI

// MARK: - Radar & Disk Platter Core Animation

struct DiskRadarScannerView: View {
    var size: CGFloat = 80
    var showHeadArm: Bool = true

    @State private var isRotating = false
    @State private var ripplePhase1 = false
    @State private var ripplePhase2 = false
    @State private var armSwing = false
    @State private var blipPulse = false

    var body: some View {
        ZStack {
            // 1. Concentric Sonar / Radar Ripples
            Circle()
                .stroke(Color.cyan.opacity(ripplePhase1 ? 0 : 0.6), lineWidth: 1.5)
                .scaleEffect(ripplePhase1 ? 1.35 : 0.65)
                .frame(width: size, height: size)

            Circle()
                .stroke(Color.blue.opacity(ripplePhase2 ? 0 : 0.5), lineWidth: 1.2)
                .scaleEffect(ripplePhase2 ? 1.5 : 0.5)
                .frame(width: size, height: size)

            // 2. Radar Base Plate (Outer Bezel & Grid)
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color(nsColor: .windowBackgroundColor).opacity(0.9),
                            Color.black.opacity(0.6)
                        ]),
                        center: .center,
                        startRadius: 2,
                        endRadius: size / 2
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [.cyan.opacity(0.6), .blue.opacity(0.3), .purple.opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                .shadow(color: .cyan.opacity(0.35), radius: 6, x: 0, y: 0)

            // 3. Coordinate Grid / Concentric Tracks
            Circle()
                .stroke(Color.cyan.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                .frame(width: size * 0.7, height: size * 0.7)

            Circle()
                .stroke(Color.cyan.opacity(0.15), lineWidth: 1)
                .frame(width: size * 0.4, height: size * 0.4)

            // Crosshairs
            Rectangle()
                .fill(Color.cyan.opacity(0.12))
                .frame(width: size * 0.9, height: 1)
            Rectangle()
                .fill(Color.cyan.opacity(0.12))
                .frame(width: 1, height: size * 0.9)

            // 4. Rotating Radar Sweep Beam
            Circle()
                .fill(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .cyan.opacity(0.05), location: 0.65),
                            .init(color: .cyan.opacity(0.25), location: 0.88),
                            .init(color: .cyan.opacity(0.75), location: 1.0)
                        ]),
                        center: .center
                    )
                )
                .frame(width: size * 0.94, height: size * 0.94)
                .rotationEffect(.degrees(isRotating ? 360 : 0))

            // Leading Radar Scanline (laser beam needle)
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.cyan.opacity(0.1), .cyan, .white],
                        startPoint: .center,
                        endPoint: .trailing
                    )
                )
                .frame(width: size * 0.47, height: 1.8)
                .offset(x: size * 0.235)
                .rotationEffect(.degrees(isRotating ? 360 : 0))

            // 5. Data Signal Blips (representing scanned files/sectors)
            Group {
                blipDot(x: size * 0.22, y: -size * 0.24, color: .cyan, delay: 0.1)
                blipDot(x: -size * 0.28, y: -size * 0.12, color: .green, delay: 0.4)
                blipDot(x: size * 0.18, y: size * 0.26, color: .mint, delay: 0.7)
                blipDot(x: -size * 0.20, y: size * 0.20, color: .blue, delay: 1.0)
            }

            // 6. Center Disk Platter / Spindle
            ZStack {
                // Spindle ring
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.7), Color(white: 0.25), Color(white: 0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size * 0.26, height: size * 0.26)
                    .shadow(color: .black.opacity(0.5), radius: 2)

                // Center glowing jewel
                Circle()
                    .fill(Color.cyan)
                    .frame(width: size * 0.10, height: size * 0.10)
                    .shadow(color: .cyan, radius: 4)

                // Head arm actuator (if enabled)
                if showHeadArm {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.9), .cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: size * 0.32, height: 2)
                        .offset(x: size * 0.16)
                        .rotationEffect(.degrees(armSwing ? 24 : -12))
                }
            }
        }
        .frame(width: size * 1.3, height: size * 1.3)
        .onAppear {
            // Start infinite rotation for the radar sweep
            withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                isRotating = true
            }
            // Ripple wave 1
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                ripplePhase1 = true
            }
            // Ripple wave 2 with stagger
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                    ripplePhase2 = true
                }
            }
            // Arm swing
            withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                armSwing = true
            }
            // Blips pulse
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                blipPulse = true
            }
        }
    }

    private func blipDot(x: CGFloat, y: CGFloat, color: Color, delay: Double) -> some View {
        Circle()
            .fill(color)
            .frame(width: 4, height: 4)
            .shadow(color: color, radius: 3)
            .opacity(blipPulse ? 0.9 : 0.2)
            .offset(x: x, y: y)
    }
}

// MARK: - Compact Scanning Card (for Dashboard & List Views)

struct DiskScanningCardView: View {
    @Bindable var store = AppStore.shared

    var body: some View {
        HStack(spacing: 16) {
            // Radar scanner icon
            DiskRadarScannerView(size: 60, showHeadArm: true)
                .frame(width: 76, height: 76)

            // Info column
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    // Pulsing active dot
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                            .shadow(color: .green, radius: 3)
                        Text("全碟深度掃描中")
                            .font(.system(size: 14, weight: .bold))
                    }

                    Spacer()

                    // Quick stop button
                    Button {
                        withAnimation {
                            store.cancelScan()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                            Text("停止掃描")
                        }
                        .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                // Stats Chips
                HStack(spacing: 16) {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .foregroundColor(.cyan)
                            .font(.caption)
                        Text("已掃描 \(store.scannedFiles.formatted()) 個檔案")
                            .font(.caption)
                            .fontWeight(.medium)
                    }

                    HStack(spacing: 5) {
                        Image(systemName: "internaldrive")
                            .foregroundColor(.blue)
                            .font(.caption)
                        Text("已分析 \(store.scannedBytes.formattedSize())")
                            .font(.caption)
                            .fontWeight(.medium)
                    }

                    if store.isRuleScanning {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.mini)
                            Text("篩選快取規則...")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Real-time current path
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(store.currentPath.isEmpty ? "正在準備檔案系統掃描..." : store.currentPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.cyan.opacity(0.10),
                            Color.blue.opacity(0.06),
                            Color(nsColor: .controlBackgroundColor).opacity(0.8)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    LinearGradient(
                        colors: [.cyan.opacity(0.45), .blue.opacity(0.2), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .padding(.horizontal, 24)
        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
    }
}

// MARK: - Full Page Scanning View (for Space Explorer or empty states)

struct DiskScanningFullView: View {
    @Bindable var store = AppStore.shared
    var title: String = "正在分析磁碟空間架構"
    var subtitle: String = "正在遍歷檔案目錄、統計大小與構建視覺化地圖..."

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            // Large Radar Graphic
            DiskRadarScannerView(size: 130, showHeadArm: true)
                .frame(width: 170, height: 170)

            // Titles
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 20, weight: .bold))

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Stats Metrics Grid
            HStack(spacing: 32) {
                statBox(
                    icon: "doc.on.doc.fill",
                    color: .cyan,
                    label: "已掃描檔案",
                    value: store.scannedFiles.formatted()
                )

                statBox(
                    icon: "externaldrive.fill",
                    color: .blue,
                    label: "累計分析大小",
                    value: store.scannedBytes.formattedSize()
                )

                statBox(
                    icon: "sparkles",
                    color: .purple,
                    label: "發現候選項目",
                    value: "\(store.candidates.count) 項"
                )
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.08))
            )

            // Current Path Indicator
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.caption2)
                        .foregroundColor(.cyan)
                    Text("當前掃描路徑")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                }

                Text(store.currentPath.isEmpty ? "初始化掃描佇列中..." : store.currentPath)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 500)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .textBackgroundColor).opacity(0.5))
                    )
            }

            // Control Action
            Button {
                withAnimation {
                    store.cancelScan()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "stop.fill")
                    Text("停止掃描")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statBox(icon: String, color: Color, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.caption)
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
        }
        .frame(minWidth: 110)
    }
}

// MARK: - Mini Scanning Status Bar (for global bottom status)

struct MiniScanStatusBar: View {
    @Bindable var store = AppStore.shared

    var body: some View {
        HStack(spacing: 12) {
            // Rotating mini radar icon
            DiskRadarScannerView(size: 20, showHeadArm: false)
                .frame(width: 24, height: 24)

            HStack(spacing: 6) {
                Text("全碟深度掃描中...")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)

                Text("已分析 \(store.scannedFiles.formatted()) 個檔案 (\(store.scannedBytes.formattedSize()))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Monospaced current path
            if !store.currentPath.isEmpty {
                Text(store.currentPath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 280)
            }

            Button {
                withAnimation {
                    store.cancelScan()
                }
            } label: {
                Text("停止")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            Color(nsColor: .windowBackgroundColor).opacity(0.95)
        )
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.cyan.opacity(0.3)),
            alignment: .top
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
