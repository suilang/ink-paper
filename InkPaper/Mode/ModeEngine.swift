import AppKit
import Foundation
import UserNotifications

@MainActor
final class ModeEngine: ObservableObject {
    @Published private(set) var activeMode: WallpaperMode?
    @Published private(set) var isBusy = false
    @Published var lastError: String?
    @Published var statusMessage: String?

    let configStore: ConfigStore
    let displayRegistry: DisplayRegistry
    let systemWallpaper: SystemWallpaperService
    let overlay: OverlayWallpaperService
    let healthChecker: HealthChecker

    private var lastReport: HealthReport?
    private var runningTask: Task<Void, Never>?
    private var pendingMessage: String?
    private var pendingWork: (@MainActor () async throws -> Void)?

    init(
        configStore: ConfigStore,
        displayRegistry: DisplayRegistry,
        systemWallpaper: SystemWallpaperService? = nil,
        overlay: OverlayWallpaperService? = nil,
        healthChecker: HealthChecker? = nil
    ) {
        self.configStore = configStore
        self.displayRegistry = displayRegistry
        self.systemWallpaper = systemWallpaper ?? SystemWallpaperService()
        self.overlay = overlay ?? OverlayWallpaperService()
        self.healthChecker = healthChecker ?? HealthChecker()

        displayRegistry.onDisplaysChanged = { [weak self] in
            Task { @MainActor in
                self?.handleDisplaysChanged()
            }
        }
    }

    func bootstrap() {
        // 不阻塞启动：先出 UI；仅在「已启用」时自动铺桌面。
        Task { @MainActor in
            if configStore.config.checkOnLaunch {
                _ = await runHealthCheck(deep: false)
            }
            if configStore.config.wallpaperEnabled {
                applyPreferredModeAsync()
            } else {
                statusMessage = "壁纸未启用（可在设置中打开「启用壁纸」）"
            }
        }
    }

    @discardableResult
    func runHealthCheck(deep: Bool) async -> HealthReport {
        let report = await healthChecker.run(
            config: configStore.config,
            displays: displayRegistry.displays,
            registry: displayRegistry,
            systemWallpaper: systemWallpaper,
            overlay: overlay,
            activeMode: activeMode,
            deepSystemCheck: deep
        )
        lastReport = report
        configStore.update { cfg in
            cfg.lastCheckAt = report.checkedAt
            cfg.lastCheckReport = report.summary
        }
        return report
    }

    /// 打开启用开关并按偏好铺到桌面。
    func enableWallpaperAsync() {
        enqueue("正在启用壁纸…") { [weak self] in
            guard let self else { return }
            let ids = self.displayRegistry.displays.map(\.id)
            guard self.configStore.config.hasUsableWallpaperImage(displayIDs: ids) else {
                throw AppError.noImageConfigured
            }
            self.configStore.update { $0.wallpaperEnabled = true }
            try await self.applyPreferredMode()
            self.statusMessage = "已启用：\(self.activeMode?.displayName ?? "未知模式")"
        }
    }

    /// 停用：停止 overlay，保留选图；不要求用户删图。
    func disableWallpaperAsync() {
        enqueue("正在停用壁纸…") { [weak self] in
            guard let self else { return }
            self.stopActiveMode(clearPublishedMode: true)
            self.configStore.update {
                $0.wallpaperEnabled = false
                $0.overlayEnabled = false
            }
            self.statusMessage = "已停用壁纸（图片仍保留）"
        }
    }

    /// 已启用时，把当前选图更新到桌面。
    func updateDesktopAsync() {
        enqueue("正在更新到桌面…") { [weak self] in
            guard let self else { return }
            guard self.configStore.config.wallpaperEnabled else {
                throw AppError.modeSwitchFailed(reason: "壁纸未启用，请先打开「启用壁纸」")
            }
            if let mode = self.activeMode {
                try await self.switchTo(mode)
            } else {
                try await self.applyPreferredMode()
            }
            self.statusMessage = "已更新到桌面（\(self.activeMode?.displayName ?? "完成")）"
        }
    }

    func applyPreferredModeAsync() {
        enqueue("正在按偏好应用…") { [weak self] in
            guard let self else { return }
            self.configStore.update { $0.wallpaperEnabled = true }
            try await self.applyPreferredMode()
        }
    }

    func switchToAsync(_ mode: WallpaperMode) {
        enqueue("正在切换到\(mode.displayName)…") { [weak self] in
            guard let self else { return }
            // 模式页显式切换：隐含启用意图。
            self.configStore.update { $0.wallpaperEnabled = true }
            try await self.switchTo(mode)
        }
    }

    func reapplyCurrentAsync() {
        updateDesktopAsync()
    }

    /// Sync overlay windows to the current display list without tearing them down first.
    /// Used after real display changes; avoids the Mission Control flash caused by stop→start.
    func syncOverlayDisplaysAsync() {
        enqueue("正在同步底层窗口…") { [weak self] in
            guard let self else { return }
            guard self.activeMode == .overlay, self.overlay.isActive else { return }
            let config = self.configStore.config
            let displays = self.displayRegistry.displays
            try self.ensureImagesReady(config: config, displays: displays)
            let prepared = try await Task.detached(priority: .userInitiated) {
                try ImagePipeline.prepareOverlayImages(config: config, displays: displays)
            }.value
            try self.overlay.applyPreparedImages(
                config: config,
                displays: displays,
                registry: self.displayRegistry,
                imagesByDisplayID: prepared
            )
            self.statusMessage = "已同步底层窗口"
        }
    }

    func applyPreferredMode() async throws {
        let preferred = configStore.config.preferredMode
        switch preferred {
        case .system:
            try await switchTo(.system)
        case .overlay:
            try await switchTo(.overlay)
        case .auto:
            // 自动模式：先做真实 MDM/托管探测；锁定则直接走底层窗口。
            let probe = systemWallpaper.probeDesktopLock()
            if probe.isLocked {
                if configStore.config.autoFallbackToOverlay {
                    try await switchTo(.overlay)
                    notifyFallbackIfNeeded(reason: probe.summary)
                    return
                }
                throw AppError.systemWallpaperUnavailable(reason: probe.summary)
            }

            let report: HealthReport
            if let lastReport {
                report = lastReport
            } else {
                report = await runHealthCheck(deep: false)
            }
            if report.systemModeWritable {
                do {
                    try await switchTo(.system)
                } catch {
                    if configStore.config.autoFallbackToOverlay {
                        try await switchTo(.overlay)
                        notifyFallbackIfNeeded(reason: error.localizedDescription)
                    } else {
                        throw error
                    }
                }
            } else if configStore.config.autoFallbackToOverlay {
                try await switchTo(.overlay)
                notifyFallbackIfNeeded(reason: "系统壁纸检查未通过")
            } else {
                throw AppError.systemWallpaperUnavailable(reason: "自动模式无法使用系统壁纸，且未开启降级")
            }
        }
    }

    func switchTo(_ mode: WallpaperMode) async throws {
        lastError = nil
        let previous = activeMode
        let config = configStore.config
        let displays = displayRegistry.displays

        try ensureImagesReady(config: config, displays: displays)

        if config.backupSystemWallpaperBeforeSwitch, mode == .overlay || previous == .system {
            systemWallpaper.backupCurrent(displays: displays, registry: displayRegistry)
        }

        // 先停旧模式，让 UI 有机会刷新 busy 状态。
        stopActiveMode(clearPublishedMode: true)
        await Task.yield()

        do {
            switch mode {
            case .system:
                try await systemWallpaper.apply(
                    config: config,
                    displays: displays,
                    registry: displayRegistry
                )
                configStore.update {
                    $0.overlayEnabled = false
                    $0.lastMode = .system
                }
                let probe = systemWallpaper.lastLockProbe
                if probe.isLocked {
                    statusMessage = "系统壁纸不可用：\(probe.summary)"
                }
            case .overlay:
                let prepared = try await Task.detached(priority: .userInitiated) {
                    try ImagePipeline.prepareOverlayImages(config: config, displays: displays)
                }.value
                await Task.yield()
                try overlay.start(
                    config: config,
                    displays: displays,
                    registry: displayRegistry,
                    imagesByDisplayID: prepared
                )
                configStore.update {
                    $0.overlayEnabled = true
                    $0.lastMode = .overlay
                }
            }
            activeMode = mode
            configStore.update { $0.wallpaperEnabled = true }
            statusMessage = "已应用：\(mode.displayName)"
        } catch {
            if let previous {
                try? await restore(mode: previous)
            }
            lastError = error.localizedDescription
            statusMessage = "应用失败"
            throw AppError.modeSwitchFailed(reason: error.localizedDescription)
        }
    }

    func stopActiveMode(clearPublishedMode: Bool = false) {
        if overlay.isActive {
            overlay.stop()
        }
        if clearPublishedMode || activeMode == .overlay {
            activeMode = nil
        }
        // 注意：不在这里改 wallpaperEnabled；停用由 disableWallpaperAsync 负责。
        configStore.update { $0.overlayEnabled = false }
    }

    func shutdown() {
        runningTask?.cancel()
        runningTask = nil
        isBusy = false
        if configStore.config.hideOnAppQuit {
            overlay.stop()
        }
        if activeMode == .overlay {
            activeMode = nil
        }
        configStore.update { $0.overlayEnabled = false }
    }

    private func enqueue(_ message: String, work: @escaping @MainActor () async throws -> Void) {
        if isBusy {
            // 合并为最新一次请求，避免「仅原生 → 改用兜底」连点时第二次被丢弃。
            pendingMessage = message
            pendingWork = work
            statusMessage = "将在当前操作完成后继续…"
            return
        }
        isBusy = true
        lastError = nil
        runningTask = Task { @MainActor in
            var currentMessage = message
            var currentWork = work
            while true {
                statusMessage = currentMessage
                lastError = nil
                do {
                    try await currentWork()
                } catch {
                    lastError = error.localizedDescription
                    statusMessage = "操作失败"
                }
                if let next = pendingWork {
                    currentWork = next
                    currentMessage = pendingMessage ?? "正在更新到桌面…"
                    pendingWork = nil
                    pendingMessage = nil
                    continue
                }
                isBusy = false
                runningTask = nil
                break
            }
        }
    }

    private func restore(mode: WallpaperMode) async throws {
        stopActiveMode(clearPublishedMode: true)
        let config = configStore.config
        let displays = displayRegistry.displays
        switch mode {
        case .system:
            try await systemWallpaper.apply(config: config, displays: displays, registry: displayRegistry)
            activeMode = .system
        case .overlay:
            let prepared = try await Task.detached(priority: .userInitiated) {
                try ImagePipeline.prepareOverlayImages(config: config, displays: displays)
            }.value
            try overlay.start(
                config: config,
                displays: displays,
                registry: displayRegistry,
                imagesByDisplayID: prepared
            )
            activeMode = .overlay
        }
    }

    private func ensureImagesReady(config: AppConfig, displays: [DisplayInfo]) throws {
        if displays.isEmpty { throw AppError.noDisplays }
        let ids = displays.map(\.id)
        let hasCoverage = config.hasUsableWallpaperImage(displayIDs: ids)
        // 允许「已启用但全部仅原生」：仍有图资源，只是当前不覆盖。
        guard hasCoverage || config.hasWallpaperImageAssets() else {
            throw AppError.noImageConfigured
        }
        guard hasCoverage else { return }
        if config.perDisplayEnabled {
            for display in displays {
                guard let path = config.imagePath(forDisplayID: display.id) else { continue }
                _ = try ImagePipeline.validate(
                    path: path,
                    maxBytes: config.maxImageBytes,
                    maxDimension: config.maxImageDimension
                )
            }
        } else {
            guard let path = config.imagePath else { throw AppError.noImageConfigured }
            _ = try ImagePipeline.validate(
                path: path,
                maxBytes: config.maxImageBytes,
                maxDimension: config.maxImageDimension
            )
        }
    }

    private func handleDisplaysChanged() {
        guard configStore.config.restoreOnDisplayChange else { return }
        guard activeMode == .overlay, overlay.isActive else { return }
        // Light sync in place — do not stop→start (that flashes system wallpaper).
        syncOverlayDisplaysAsync()
    }

    private func notifyFallbackIfNeeded(reason: String) {
        guard configStore.config.notifyOnFallback else { return }
        statusMessage = "已降级到底层窗口：\(reason)"
        let content = UNMutableNotificationContent()
        content.title = "Ink Paper"
        content.body = "系统壁纸不可用，已切换到底层窗口模式。"
        let req = UNNotificationRequest(
            identifier: "fallback-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
}
