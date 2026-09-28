import AppKit
import SwiftUI

/// 设置面板跨页共享的运行态与 helper。
///
/// 拆分前这些状态散落在 `SettingsRootView` 的 `@State` 里；现在集中托管，
/// 各 Page 通过 `@ObservedObject` 订阅，避免重复持有与重复 `.disabled` 链。
@MainActor
final class SettingsSharedState: ObservableObject {
    @Published var healthItems: [CheckItemResult] = []
    @Published var healthCheckedAt: Date?
    @Published var alertMessage: String?
    @Published var previewImage: NSImage?
    @Published var statusBanner: String?
    @Published var reapplyDebounceTask: Task<Void, Never>?

    weak var configStore: ConfigStore?
    weak var modeEngine: ModeEngine?
    weak var displayRegistry: DisplayRegistry?
    weak var standReminder: StandReminderEngine?

    func bind(
        to configStore: ConfigStore,
        modeEngine: ModeEngine,
        displayRegistry: DisplayRegistry,
        standReminder: StandReminderEngine
    ) {
        self.configStore = configStore
        self.modeEngine = modeEngine
        self.displayRegistry = displayRegistry
        self.standReminder = standReminder
    }

    /// 通用配置字段双向绑定（与原 `binding` 同语义）。
    func binding<T>(_ keyPath: WritableKeyPath<AppConfig, T>) -> Binding<T> {
        Binding(
            get: { self.configStore?.config[keyPath: keyPath] ?? AppConfig.default[keyPath: keyPath] },
            set: { value in self.configStore?.update { $0[keyPath: keyPath] = value } }
        )
    }

    /// 已启用时把当前配置立刻重铺到桌面（选图/换图/改缩放等直接生效）。
    func reapplyIfEnabled(debounceMilliseconds: UInt64 = 0) {
        guard let configStore, let modeEngine else { return }
        guard configStore.config.wallpaperEnabled else { return }
        let ids = displayRegistry?.displays.map(\.id) ?? []
        let canApply = configStore.config.hasUsableWallpaperImage(displayIDs: ids)
        guard canApply || configStore.config.hasWallpaperImageAssets() else { return }

        // busy 期间不排队新工作，避免与 ModeEngine.pendingWork 叠加卡住 MainActor。
        guard !modeEngine.isBusy else { return }

        if debounceMilliseconds > 0 {
            reapplyDebounceTask?.cancel()
            reapplyDebounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: debounceMilliseconds * 1_000_000)
                guard !Task.isCancelled else { return }
                // 外层已解包 configStore/modeEngine（强引用，闭包内安全）；
                // 只需复查启用与 busy 状态，避免 sleep 期间被停用或叠操作。
                guard configStore.config.wallpaperEnabled, !modeEngine.isBusy else { return }
                modeEngine.updateDesktopAsync()
            }
            return
        }
        modeEngine.updateDesktopAsync()
    }

    func reloadPreview() {
        guard let configStore else { return }
        let path = configStore.config.imagePath
        guard let path else {
            previewImage = nil
            return
        }
        // 缩略图异步加载，避免切回壁纸 Tab 时主线程读大图卡死。
        Task.detached(priority: .utility) {
            let image = ImagePipeline.loadThumbnail(path: path, maxPixelSize: 512)
            await MainActor.run { [weak self] in
                guard let self, let cs = self.configStore, cs.config.imagePath == path else { return }
                self.previewImage = image
            }
        }
    }

    func presentOpenPanel(onPick: @escaping (URL) -> Void) {
        DispatchQueue.main.async { [weak self] in
            let panel = NSOpenPanel()
            panel.allowedContentTypes = ImagePipeline.allowedContentTypes
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.title = "选择壁纸图片"
            panel.begin { response in
                guard response == .OK, let url = panel.url else {
                    self?.statusBanner = "已取消选图"
                    return
                }
                onPick(url)
            }
        }
    }
}
