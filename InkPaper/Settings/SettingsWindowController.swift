import AppKit
import SwiftUI

/// 保留文件：设置窗主要由 SwiftUI `Window` scene + AppDelegate 兜底创建。
/// 此类不再作为主路径。
@MainActor
enum SettingsPresentation {
    static func present(
        configStore: ConfigStore,
        modeEngine: ModeEngine,
        displayRegistry: DisplayRegistry
    ) -> NSWindow {
        let root = SettingsRootView(
            configStore: configStore,
            modeEngine: modeEngine,
            displayRegistry: displayRegistry
        )
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Ink Paper 设置"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 780, height: 520))
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return window
    }
}
