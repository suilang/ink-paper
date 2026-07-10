import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static weak var shared: AppDelegate?
    private var fallbackWindow: NSWindow?
    private var singleInstanceObserver: NSObjectProtocol?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // 必须在 bootstrap 之前：避免第二份进程再铺一层 overlay。
        if !SingleInstance.acquireOrHandOff() {
            exit(0)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self

        singleInstanceObserver = SingleInstance.startListeningForActivation {
            AppDelegate.openSettings()
        }

        // 菜单栏常驻，不占 Dock。
        NSApp.setActivationPolicy(.accessory)

        let services = AppServices.shared
        services.notifier.requestAuthorizationIfNeeded()
        services.modeEngine.bootstrap()

        // 延后打开，等 SwiftUI Window scene 物化完成。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if services.configStore.config.openConfigOnLaunch
                || services.configStore.config.imagePath == nil
                || !services.configStore.config.wallpaperEnabled {
                Self.openSettings()
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let singleInstanceObserver {
            DistributedNotificationCenter.default().removeObserver(singleInstanceObserver)
            self.singleInstanceObserver = nil
        }
        AppServices.shared.modeEngine.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Self.openSettings()
        return true
    }

    static func openSettings() {
        NSApp.activate(ignoringOtherApps: true)

        let candidates = NSApp.windows.filter { window in
            let title = window.title
            return title.contains("Ink Paper") || title.contains("设置") || window.isVisible
        }

        // 优先找尺寸像设置窗的普通窗口（排除菜单栏相关矮窗）。
        if let window = candidates.first(where: { $0.frame.height > 200 })
            ?? NSApp.windows.first(where: { $0.frame.height > 200 && $0.canBecomeKey }) {
            window.title = "Ink Paper 设置"
            window.level = .floating
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            // 恢复普通层级，避免一直盖住其他应用。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                window.level = .normal
            }
            return
        }

        shared?.ensureFallbackSettingsWindow()
    }

    private func ensureFallbackSettingsWindow() {
        if let fallbackWindow {
            fallbackWindow.title = "Ink Paper 设置"
            fallbackWindow.level = .floating
            fallbackWindow.makeKeyAndOrderFront(nil)
            fallbackWindow.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                fallbackWindow.level = .normal
            }
            return
        }
        let services = AppServices.shared
        let root = SettingsRootView(
            configStore: services.configStore,
            modeEngine: services.modeEngine,
            displayRegistry: services.displayRegistry
        )
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Ink Paper 设置"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 780, height: 520))
        window.isReleasedWhenClosed = false
        window.center()
        window.level = .floating
        fallbackWindow = window
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            window.level = .normal
        }
    }
}
