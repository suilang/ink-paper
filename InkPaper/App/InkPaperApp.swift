import AppKit
import SwiftUI

@main
struct InkPaperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var services = AppServices.shared

    var body: some Scene {
        Window("Ink Paper 设置", id: "settings") {
            SettingsRootView(
                configStore: services.configStore,
                modeEngine: services.modeEngine,
                displayRegistry: services.displayRegistry
            )
            .frame(minWidth: 760, minHeight: 520)
            .onAppear {
                DispatchQueue.main.async {
                    AppDelegate.openSettings()
                }
            }
        }
        .defaultSize(width: 800, height: 540)
        .commandsRemoved()

        MenuBarExtra {
            MenuBarMenuContent()
        } label: {
            Label("Ink", systemImage: "photo.on.rectangle")
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuBarMenuContent: View {
    @ObservedObject private var modeEngine = AppServices.shared.modeEngine
    @ObservedObject private var configStore = AppServices.shared.configStore

    var body: some View {
        let mode = modeEngine.activeMode?.displayName ?? "未启用"
        Text("当前模式：\(mode)")
        Text(configStore.config.wallpaperEnabled ? "壁纸：已启用" : "壁纸：未启用")
        if modeEngine.isBusy {
            Text("处理中…")
        }
        Divider()
        Button("打开设置…") {
            AppDelegate.openSettings()
        }
        if configStore.config.wallpaperEnabled {
            Button("停用壁纸") {
                modeEngine.disableWallpaperAsync()
            }
            .disabled(modeEngine.isBusy)
        } else {
            Button("启用壁纸…") {
                modeEngine.enableWallpaperAsync()
            }
            .disabled(modeEngine.isBusy)
        }
        Divider()
        Button("切换到系统壁纸模式") {
            modeEngine.switchToAsync(.system)
        }
        .disabled(modeEngine.isBusy)
        Button("切换到底层窗口模式") {
            modeEngine.switchToAsync(.overlay)
        }
        .disabled(modeEngine.isBusy)
        Divider()
        Button("运行诊断") {
            Task {
                _ = await modeEngine.runHealthCheck(deep: false)
                AppDelegate.openSettings()
            }
        }
        Divider()
        Button("退出 Ink Paper") {
            NSApp.terminate(nil)
        }
    }
}
