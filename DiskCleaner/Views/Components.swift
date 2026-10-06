//
//  Components.swift
//  DiskCleaner
//
//  Shared reusable UI components: badges, banners, progress bars and buttons.
//

import SwiftUI

struct SafetyBadge: View {
    let safety: Safety

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(safety.label)
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12))
        .foregroundColor(color)
        .clipShape(Capsule())
    }

    private var color: Color {
        switch safety {
        case .safe: return .green
        case .caution: return .orange
        case .review: return .red
        }
    }
}

struct FDABanner: View {
    @Bindable var store = AppStore.shared

    var body: some View {
        if !store.hasFullDiskAccess && !store.fdaBannerDismissed {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundColor(.orange)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("建議開啟「完整磁碟取用權限」")
                        .font(.system(size: 13, weight: .semibold))
                    Text("若未授權，系統日誌、部分快取與隱藏設定將無法完整掃描。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("開啟系統設定") {
                    FullDiskAccess.openSettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    store.recheckPermission()
                } label: {
                    Label("重新檢查", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    store.fdaBannerDismissed = true
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("略過")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.orange.opacity(0.1))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color.orange.opacity(0.3)),
                alignment: .bottom
            )
        }
    }
}

struct SizeBar: View {
    let value: Int64
    let max: Int64
    var color: Color = .blue

    var body: some View {
        GeometryReader { geo in
            let ratio = max > 0 ? CGFloat(clamp(Double(value) / Double(max))) : 0
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                Capsule()
                    .fill(color)
                    .frame(width: max > 0 ? Swift.max(4, geo.size.width * ratio) : 0)
            }
        }
        .frame(height: 6)
    }

    private func clamp(_ v: Double) -> Double { Swift.min(Swift.max(v, 0), 1) }
}
