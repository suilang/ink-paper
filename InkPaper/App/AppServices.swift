import Foundation

/// 进程内共享服务，供 SwiftUI Scene 与 AppDelegate 共用。
@MainActor
final class AppServices: ObservableObject {
    static let shared = AppServices()

    let configStore: ConfigStore
    let displayRegistry: DisplayRegistry
    let modeEngine: ModeEngine
    let notifier: AppNotifier

    private init() {
        let configStore = ConfigStore()
        let displayRegistry = DisplayRegistry()
        self.configStore = configStore
        self.displayRegistry = displayRegistry
        self.modeEngine = ModeEngine(configStore: configStore, displayRegistry: displayRegistry)
        self.notifier = AppNotifier()
    }
}
