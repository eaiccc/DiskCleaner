//
//  ContentView.swift
//  DiskCleaner
//
//  Main split navigation connecting sidebar, detail views, bottom basket bar and sheets.
//

import SwiftUI
import SwiftData

enum SidebarSection: String, Hashable, CaseIterable, Identifiable {
    case overview = "總覽"
    case explorer = "空間地圖"
    case xcode = "Xcode"
    case simulator = "模擬器"
    case ai = "AI 工具快取"
    case tempLogs = "暫存與 Log"
    case packages = "套件快取"
    case largeFiles = "大型檔案"
    case history = "清理歷史"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "chart.pie.fill"
        case .explorer: return "folder.fill"
        case .xcode: return "hammer.fill"
        case .simulator: return "iphone"
        case .ai: return "brain.head.profile"
        case .tempLogs: return "doc.text.fill"
        case .packages: return "shippingbox.fill"
        case .largeFiles: return "archivebox.fill"
        case .history: return "clock.arrow.circlepath"
        }
    }
}

struct ContentView: View {
    @Bindable var store = AppStore.shared
    @State private var selectedSection: SidebarSection = .overview

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $selectedSection) { section in
                NavigationLink(value: section) {
                    Label(section.rawValue, systemImage: section.icon)
                        .padding(.vertical, 4)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    // Scan button
                    if store.isScanning {
                        Button {
                            withAnimation {
                                store.cancelScan()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                                ProgressView()
                                    .controlSize(.small)
                                Text("停止掃描")
                            }
                        }
                    } else {
                        Button {
                            withAnimation {
                                store.startScan()
                            }
                        } label: {
                            Label("全碟掃描", systemImage: "arrow.clockwise")
                        }
                    }
                }
            }
        } detail: {
            VStack(spacing: 0) {
                // Main Content
                switch selectedSection {
                case .overview:
                    OverviewView { target in
                        selectedSection = target
                    }
                case .explorer:
                    SpaceExplorerView()
                case .xcode:
                    CandidateListView(
                        categories: [.xcode],
                        title: "Xcode 開發檔案",
                        subtitle: "DerivedData 建置快取、Previews、DeviceSupport 與 Archives 封存"
                    )
                case .simulator:
                    CandidateListView(
                        categories: [.simulator],
                        title: "模擬器與裝置",
                        subtitle: "不可用裝置、舊版 Runtime、測試快照，安全使用 simctl 管理"
                    )
                case .ai:
                    CandidateListView(
                        categories: [.ai],
                        title: "AI 工具快取",
                        subtitle: "HuggingFace、Ollama、LM Studio 模型與 Cursor / VS Code / Claude 快取"
                    )
                case .tempLogs:
                    CandidateListView(
                        categories: [.tempLogs],
                        title: "暫存檔與系統 Log",
                        subtitle: "$TMPDIR、/tmp 舊檔、當機診斷報告與應用程式執行日誌"
                    )
                case .packages:
                    CandidateListView(
                        categories: [.packages],
                        title: "專案與套件快取",
                        subtitle: "SwiftPM、CocoaPods、npm、Gradle 快取與專案 node_modules / .build"
                    )
                case .largeFiles:
                    LargeFilesView()
                case .history:
                    HistoryView()
                }

                // Global live scan status when viewing other detail views
                if store.isScanning && selectedSection != .overview {
                    MiniScanStatusBar()
                }

                // Persistent Bottom Basket Bar
                BasketBar()
            }
        }
        .frame(minWidth: 1000, minHeight: 650)
        // Cleanup flow sheets
        .sheet(isPresented: Binding(
            get: { store.cleanupPhase == .confirming },
            set: { if !$0 { store.cancelConfirmation() } }
        )) {
            CleanupConfirmationSheet()
        }
        .sheet(isPresented: Binding(
            get: { store.cleanupPhase == .running },
            set: { _ in }
        )) {
            CleanupProgressSheet()
        }
        .sheet(isPresented: Binding(
            get: { store.cleanupPhase == .finished },
            set: { if !$0 { store.dismissCleanup() } }
        )) {
            CleanupReportSheet()
        }
    }
}
