import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsRootView: View {
    @ObservedObject var configStore: ConfigStore
    @ObservedObject var modeEngine: ModeEngine
    @ObservedObject var displayRegistry: DisplayRegistry

    @StateObject private var state = SettingsSharedState()
    @State private var selectedTab: SettingsTab = .wallpaperMode

    enum SettingsTab: String, CaseIterable, Identifiable {
        case wallpaperMode, general, diagnostics, reminder, about
        var id: String { rawValue }
        var title: String {
            switch self {
            case .wallpaperMode: return "壁纸与模式"
            case .general: return "通用"
            case .diagnostics: return "诊断"
            case .reminder: return "提醒"
            case .about: return "关于"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if modeEngine.isBusy || state.statusBanner != nil || modeEngine.statusMessage != nil || modeEngine.lastError != nil {
                statusBar
            }

            TabView(selection: $selectedTab) {
                WallpaperModePage(state: state)
                    .tabItem { Label("壁纸与模式", systemImage: "photo.on.rectangle") }
                    .tag(SettingsTab.wallpaperMode)

                GeneralPage(state: state)
                    .tabItem { Label("通用", systemImage: "gearshape") }
                    .tag(SettingsTab.general)

                DiagnosticsPage(state: state)
                    .tabItem { Label("诊断", systemImage: "stethoscope") }
                    .tag(SettingsTab.diagnostics)

                ReminderPage(configStore: AppServices.shared.configStore, standReminder: AppServices.shared.standReminder)
                    .tabItem { Label("提醒", systemImage: "figure.stand") }
                    .tag(SettingsTab.reminder)

                AboutPage()
                    .tabItem { Label("关于", systemImage: "info.circle") }
                    .tag(SettingsTab.about)
            }
            .padding(12)
        }
        .frame(minWidth: 760, minHeight: 520)
        .disabled(modeEngine.isBusy)
        .overlay {
            if modeEngine.isBusy {
                ProgressView("处理中…")
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .alert("提示", isPresented: Binding(
            get: { state.alertMessage != nil },
            set: { if !$0 { state.alertMessage = nil } }
        )) {
            Button("好", role: .cancel) { state.alertMessage = nil }
        } message: {
            Text(state.alertMessage ?? "")
        }
        .onAppear {
            let services = AppServices.shared
            state.bind(
                to: services.configStore,
                modeEngine: services.modeEngine,
                displayRegistry: services.displayRegistry,
                standReminder: services.standReminder
            )
            state.reloadPreview()
        }
        .onChange(of: configStore.config.imagePath) { _ in state.reloadPreview() }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if modeEngine.isBusy {
                ProgressView().controlSize(.small)
            }
            Text(modeEngine.lastError ?? state.statusBanner ?? modeEngine.statusMessage ?? "")
                .font(.caption)
                .foregroundStyle(modeEngine.lastError == nil ? Color.secondary : Color.red)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
