import AppKit
import SwiftUI

/// 壁纸与模式融合页：启用区 → 模式 → 分屏 → 全局图 → 缩放 → 危险操作。
///
/// 由原 `wallpaperPage` 与 `modePage` 合并而来（见 settings-ui 文档）。
struct WallpaperModePage: View {
    @ObservedObject var state: SettingsSharedState

    private var configStore: ConfigStore? { state.configStore }
    private var modeEngine: ModeEngine? { state.modeEngine }
    private var displayRegistry: DisplayRegistry? { state.displayRegistry }

    var body: some View {
        Form {
            Section {
                enableWallpaperControls
            } header: {
                Text("启用")
            } footer: {
                Text("打开「启用壁纸」后桌面立即生效；之后选图、换图会直接更新桌面。停用不会删除已选图片。")
                    .font(.caption)
            }

            modeSection

            Section {
                Toggle(
                    "按显示器分别设置",
                    isOn: Binding(
                        get: { configStore?.config.perDisplayEnabled ?? false },
                        set: { enabled in
                            configStore?.update { $0.perDisplayEnabled = enabled }
                            if enabled {
                                state.statusBanner = "已开启分屏：可为每块屏幕选图，或指定仅用原生壁纸"
                            } else {
                                state.statusBanner = "已关闭分屏，将使用全局图片"
                            }
                            state.reapplyIfEnabled()
                        }
                    )
                )
            } footer: {
                Text("开启后可为每块屏单独选图；也可让某块屏不覆盖，仅保留系统原生壁纸。")
                    .font(.caption)
            }

            if let tip = displayRegistry?.lastChangeMessage {
                Section {
                    Text(tip).foregroundStyle(.orange)
                }
            }

            if configStore?.config.perDisplayEnabled == true {
                Section("各显示器壁纸") {
                    let displays = displayRegistry?.displays ?? []
                    if displays.isEmpty {
                        Text("未检测到显示器").foregroundStyle(.secondary)
                    } else {
                        ForEach(displays) { display in
                            displayPickerRow(display)
                        }
                    }
                    Button("刷新显示器列表") {
                        displayRegistry?.refresh()
                        state.statusBanner = "已刷新显示器列表（\(displayRegistry?.displays.count ?? 0) 块）"
                    }
                    .disabled(modeEngine?.isBusy ?? false)
                }
            }

            Section(configStore?.config.perDisplayEnabled == true ? "全局兜底图片" : "全局图片") {
                globalImageSection
            }

            Section("缩放") {
                scaleSection
            }

            if hasAnySelectedImage {
                Section {
                    Button("清除全部已选壁纸", role: .destructive) {
                        clearAllImages()
                    }
                    .disabled(modeEngine?.isBusy ?? false)
                } footer: {
                    Text("清除图片后会自动停用。若只想暂时不显示，请关闭上方「启用壁纸」。")
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }

    // MARK: - Enable

    private var enableWallpaperControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(
                "启用壁纸",
                isOn: Binding(
                    get: { configStore?.config.wallpaperEnabled ?? false },
                    set: { enabled in
                        guard let modeEngine else { return }
                        if enabled {
                            guard canApplyWallpaper else {
                                state.alertMessage = "请先选择至少一张壁纸图片，再启用"
                                return
                            }
                            state.statusBanner = "正在启用壁纸…"
                            modeEngine.enableWallpaperAsync()
                        } else {
                            state.statusBanner = "正在停用壁纸…"
                            modeEngine.disableWallpaperAsync()
                        }
                    }
                )
            )
            .disabled((modeEngine?.isBusy ?? false) || (!(configStore?.config.wallpaperEnabled ?? false) && !canApplyWallpaper))

            HStack(spacing: 8) {
                statusBadge
                if modeEngine?.isBusy ?? false {
                    ProgressView().controlSize(.small)
                }
            }

            Text(enableHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusBadge: some View {
        let text: String
        let color: Color
        let busy = modeEngine?.isBusy ?? false
        let enabled = configStore?.config.wallpaperEnabled ?? false
        if busy {
            text = "处理中"
            color = .orange
        } else if modeEngine?.lastError != nil, enabled {
            text = "失败"
            color = .red
        } else if enabled, let mode = modeEngine?.activeMode {
            text = "运行中 · \(mode.displayName)"
            color = .green
        } else if enabled {
            text = "已启用（等待生效）"
            color = .orange
        } else if canApplyWallpaper {
            text = "已选图 · 未启用"
            color = .secondary
        } else {
            text = "未选图 · 未启用"
            color = .secondary
        }
        return Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var enableHelpText: String {
        if !canApplyWallpaper {
            return "先在下方选择图片；未启用时选图不会改变桌面。"
        }
        if configStore?.config.wallpaperEnabled ?? false {
            return "已启用。选图、换图、改缩放会直接更新桌面。关闭开关即可停用（不必删图）。"
        }
        return "图片已就绪。打开「启用壁纸」后才会铺到桌面。"
    }

    // MARK: - Mode

    @ViewBuilder
    private var modeSection: some View {
        Section("模式") {
            Picker(
                "偏好模式",
                selection: Binding(
                    get: { configStore?.config.preferredMode ?? .auto },
                    set: { value in
                        configStore?.update { $0.preferredMode = value }
                        state.statusBanner = "偏好已改为「\(value.displayName)」，点击下方按钮才会真正切换"
                    }
                )
            ) {
                ForEach(PreferredMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .disabled(modeEngine?.isBusy ?? false)

            Toggle("系统壁纸失败时自动降级到底层窗口", isOn: state.binding(\.autoFallbackToOverlay))
            Toggle("降级时通知", isOn: state.binding(\.notifyOnFallback))
            Toggle("切换前备份系统壁纸", isOn: state.binding(\.backupSystemWallpaperBeforeSwitch))
            Toggle("底层窗口出现在所有 Space", isOn: state.binding(\.applyToAllSpaces))

            if let probe = modeEngine?.systemWallpaper.lastLockProbe {
                Divider()
                LabeledContent("系统壁纸策略") {
                    Text(probe.isLocked ? "已锁定（MDM）" : "可写")
                        .foregroundStyle(probe.isLocked ? Color.orange : Color.secondary)
                }
                if probe.isLocked {
                    Text(probe.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("自动模式下会改用底层窗口。强制系统壁纸会失败。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            LabeledContent("当前模式") {
                Text(modeEngine?.activeMode?.displayName ?? "未启用")
            }

            HStack {
                Button("按偏好立即应用（并启用）") {
                    state.statusBanner = "正在按偏好应用…"
                    modeEngine?.applyPreferredModeAsync()
                }
                .disabled(modeEngine?.isBusy ?? false || !canApplyWallpaper)

                Button("切换到系统壁纸（并启用）") {
                    state.statusBanner = "正在切换到系统壁纸…"
                    modeEngine?.switchToAsync(.system)
                }
                .disabled(modeEngine?.isBusy ?? false || !canApplyWallpaper)

                Button("切换到底层窗口（并启用）") {
                    state.statusBanner = "正在切换到底层窗口…"
                    modeEngine?.switchToAsync(.overlay)
                }
                .disabled(modeEngine?.isBusy ?? false || !canApplyWallpaper)
            }

            if configStore?.config.wallpaperEnabled ?? false {
                Button("停用壁纸", role: .destructive) {
                    state.statusBanner = "正在停用壁纸…"
                    modeEngine?.disableWallpaperAsync()
                }
                .disabled(modeEngine?.isBusy ?? false)
            }
        }
    }

    // MARK: - Per display

    private func displayPickerRow(_ display: DisplayInfo) -> some View {
        let path = effectivePath(for: display.id)
        let isNative = configStore?.config.usesNativeWallpaperOnly(forDisplayID: display.id) ?? false
        let hasCustom: Bool = {
            if let p = configStore?.config.perDisplayMap[display.id], !p.isEmpty { return true }
            return false
        }()
        return HStack(alignment: .top, spacing: 12) {
            DisplayThumbnail(path: isNative ? nil : path, nativeOnly: isNative)
                .frame(width: 96, height: 64)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(display.localizedName).font(.headline)
                    if display.isMain {
                        Text("主屏")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }
                    Spacer()
                    Text(display.resolutionDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("ID: \(display.id)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Text(shortPathLabel(for: display.id))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack {
                    Button("选择图片…") {
                        pickImage(for: display.id)
                    }
                    .disabled(modeEngine?.isBusy ?? false)

                    if isNative {
                        Button("恢复覆盖") {
                            restoreCoverage(displayID: display.id, displayName: display.localizedName)
                        }
                        .disabled(modeEngine?.isBusy ?? false)
                    } else if hasCustom {
                        Button("改用兜底图") {
                            useGlobalFallback(displayID: display.id, displayName: display.localizedName)
                        }
                        .disabled(modeEngine?.isBusy ?? false)
                    }

                    if !isNative {
                        Button("仅原生壁纸", role: .destructive) {
                            setNativeOnly(displayID: display.id, displayName: display.localizedName)
                        }
                        .disabled(modeEngine?.isBusy ?? false)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Global image

    @ViewBuilder
    private var globalImageSection: some View {
        HStack(alignment: .top, spacing: 16) {
            thumbnailBox(image: state.previewImage, emptyText: configStore?.config.imagePath == nil ? "无预览" : "加载中…")
                .frame(width: 220, height: 140)

            VStack(alignment: .leading, spacing: 8) {
                Text(selectionCaption(path: configStore?.config.imagePath))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                HStack {
                    Button(configStore?.config.perDisplayEnabled == true ? "选择兜底图…" : "选择图片…") {
                        pickGlobalImage()
                    }
                    .disabled(modeEngine?.isBusy ?? false)

                    if configStore?.config.imagePath != nil {
                        Button("移除", role: .destructive) {
                            clearGlobalImage()
                        }
                        .disabled(modeEngine?.isBusy ?? false)
                    }
                }

                if configStore?.config.imagePath != nil, !(configStore?.config.wallpaperEnabled ?? false) {
                    Text("已选图，打开上方「启用壁纸」后才会铺到桌面")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                if configStore?.config.perDisplayEnabled == true {
                    Text("未单独选图的屏幕会使用这张兜底图；标记为「仅原生」的屏幕不会使用。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var scaleSection: some View {
        Picker(
            "策略",
            selection: Binding(
                get: { configStore?.config.scaleMode ?? .fill },
                set: { mode in
                    configStore?.update { $0.scaleMode = mode }
                    state.statusBanner = "缩放已改为「\(mode.displayName)」"
                    state.reapplyIfEnabled()
                }
            )
        ) {
            ForEach(ScaleMode.allCases) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .disabled(modeEngine?.isBusy ?? false)
        if configStore?.config.scaleMode == .fit {
            ColorPicker(
                "留边颜色",
                selection: Binding(
                    get: { Color(nsColor: (configStore?.config.fitBackgroundColor ?? .black).nsColor) },
                    set: { color in
                        configStore?.update {
                            $0.fitBackgroundColor = RGBAColor(nsColor: NSColor(color))
                        }
                        state.statusBanner = "已更新留边颜色"
                        state.reapplyIfEnabled(debounceMilliseconds: 400)
                    }
                )
            )
            .disabled(modeEngine?.isBusy ?? false)
        }
    }

    // MARK: - Helpers

    private var canApplyWallpaper: Bool {
        guard let configStore, let displayRegistry else { return false }
        return configStore.config.hasUsableWallpaperImage(displayIDs: displayRegistry.displays.map(\.id))
    }

    private var hasAnySelectedImage: Bool {
        if configStore?.config.imagePath != nil { return true }
        return (configStore?.config.perDisplayMap.values.contains { !$0.isEmpty }) ?? false
    }

    private func effectivePath(for displayID: String) -> String? {
        configStore?.config.imagePath(forDisplayID: displayID)
    }

    private func selectionCaption(path: String?) -> String {
        guard let path else { return "未选择" }
        let name = URL(fileURLWithPath: path).lastPathComponent
        if configStore?.config.wallpaperEnabled ?? false {
            return "已选：\(name)"
        }
        return "已选：\(name)（尚未启用）"
    }

    private func shortPathLabel(for displayID: String) -> String {
        guard let config = configStore?.config else { return "" }
        if config.usesNativeWallpaperOnly(forDisplayID: displayID) {
            if let path = config.perDisplayMap[displayID], !path.isEmpty {
                let name = URL(fileURLWithPath: path).lastPathComponent
                return "仅原生壁纸（已保留分屏图：\(name)）"
            }
            if let global = config.imagePath {
                return "仅原生壁纸（恢复后可用兜底：\(URL(fileURLWithPath: global).lastPathComponent)）"
            }
            return "仅原生壁纸（不覆盖）"
        }
        if let path = config.perDisplayMap[displayID], !path.isEmpty {
            let name = URL(fileURLWithPath: path).lastPathComponent
            return config.wallpaperEnabled ? "已选：\(name)" : "已选：\(name)（尚未启用）"
        }
        if let global = config.imagePath {
            return "未单独选图 → 兜底：\(URL(fileURLWithPath: global).lastPathComponent)"
        }
        return "尚未选图（也无兜底图）"
    }

    @ViewBuilder
    private func thumbnailBox(image: NSImage?, emptyText: String) -> some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Text(emptyText).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .clipped()
    }

    // MARK: - Actions

    private func clearGlobalImage() {
        guard let configStore else { return }
        let old = configStore.config.imagePath
        configStore.update { $0.imagePath = nil }
        if let old { ImagePipeline.invalidate(path: old) }
        state.previewImage = nil
        state.statusBanner = "已移除全局图片"
        if configStore.config.wallpaperEnabled, canApplyWallpaper {
            state.reapplyIfEnabled()
        } else {
            autoDisableIfNoImageLeft()
        }
    }

    private func useGlobalFallback(displayID: String, displayName: String) {
        guard let configStore else { return }
        let old = configStore.config.perDisplayMap[displayID]
        configStore.update {
            $0.perDisplayNativeIDs.remove(displayID)
            $0.perDisplayMap.removeValue(forKey: displayID)
        }
        if let old, !old.isEmpty { ImagePipeline.invalidate(path: old) }
        guard configStore.config.imagePath != nil else {
            state.statusBanner = "\(displayName) 已改回兜底，但尚未设置兜底图"
            state.alertMessage = "请先在下方选择全局兜底图片"
            autoDisableIfNoImageLeft()
            return
        }
        state.statusBanner = "\(displayName) 已改为使用兜底图"
        applyDesktopAfterConfigChange()
    }

    private func restoreCoverage(displayID: String, displayName: String) {
        guard let configStore else { return }
        configStore.update {
            $0.perDisplayNativeIDs.remove(displayID)
            if let path = $0.perDisplayMap[displayID], path.isEmpty {
                $0.perDisplayMap.removeValue(forKey: displayID)
            }
        }
        let path = configStore.config.imagePath(forDisplayID: displayID)
        guard path != nil else {
            state.statusBanner = "\(displayName) 已取消仅原生，但没有可铺的图片"
            state.alertMessage = "请为该屏选择图片，或先设置全局兜底图"
            autoDisableIfNoImageLeft()
            return
        }
        state.statusBanner = "\(displayName) 已恢复覆盖"
        applyDesktopAfterConfigChange()
    }

    private func setNativeOnly(displayID: String, displayName: String) {
        guard let configStore, let modeEngine else { return }
        configStore.update {
            $0.perDisplayNativeIDs.insert(displayID)
            if let path = $0.perDisplayMap[displayID], path.isEmpty {
                $0.perDisplayMap.removeValue(forKey: displayID)
            }
        }
        state.statusBanner = "\(displayName) 已设为仅原生壁纸（不覆盖）"
        if configStore.config.wallpaperEnabled {
            modeEngine.updateDesktopAsync()
        }
    }

    private func clearAllImages() {
        guard let configStore else { return }
        let oldGlobal = configStore.config.imagePath
        let oldMap = configStore.config.perDisplayMap
        configStore.update {
            $0.imagePath = nil
            $0.perDisplayMap = [:]
            $0.perDisplayNativeIDs = []
        }
        ImagePipeline.invalidateCache()
        if let oldGlobal { ImagePipeline.invalidate(path: oldGlobal) }
        for path in oldMap.values where !path.isEmpty { ImagePipeline.invalidate(path: path) }
        state.previewImage = nil
        state.statusBanner = "已清除全部已选壁纸"
        autoDisableIfNoImageLeft(force: true)
    }

    private func autoDisableIfNoImageLeft(force: Bool = false) {
        guard let configStore, let modeEngine else { return }
        let noAssets = force || !configStore.config.hasWallpaperImageAssets()
        guard noAssets else { return }
        if configStore.config.wallpaperEnabled || modeEngine.overlay.isActive || modeEngine.activeMode != nil {
            modeEngine.disableWallpaperAsync()
            state.statusBanner = (state.statusBanner ?? "") + "；已自动停用"
        }
    }

    private func applyDesktopAfterConfigChange() {
        guard let configStore, let modeEngine else { return }
        if configStore.config.wallpaperEnabled {
            if canApplyWallpaper {
                modeEngine.updateDesktopAsync()
            } else if configStore.config.hasWallpaperImageAssets() {
                modeEngine.updateDesktopAsync()
            } else {
                autoDisableIfNoImageLeft()
            }
        } else if canApplyWallpaper {
            state.statusBanner = (state.statusBanner ?? "") + "，正在重新启用…"
            modeEngine.enableWallpaperAsync()
        }
    }

    private func pickGlobalImage() {
        state.presentOpenPanel { url in
            guard let configStore else { return }
            configStore.update { $0.imagePath = url.path }
            ImagePipeline.invalidate(path: url.path)
            state.reloadPreview()
            let name = url.lastPathComponent
            if configStore.config.wallpaperEnabled {
                state.statusBanner = "已选择「\(name)」，正在应用到桌面…"
                state.reapplyIfEnabled()
            } else {
                state.statusBanner = "已选择「\(name)」（尚未启用）"
            }
        }
    }

    private func pickImage(for displayID: String) {
        guard let configStore, let displayRegistry else { return }
        state.presentOpenPanel { url in
            let name = displayRegistry.displays.first(where: { $0.id == displayID })?.localizedName ?? "该屏"
            configStore.update {
                $0.perDisplayEnabled = true
                $0.perDisplayMap[displayID] = url.path
                $0.perDisplayNativeIDs.remove(displayID)
            }
            ImagePipeline.invalidate(path: url.path)
            if configStore.config.wallpaperEnabled {
                state.statusBanner = "已为\(name)选择「\(url.lastPathComponent)」，正在应用到桌面…"
                state.reapplyIfEnabled()
            } else {
                state.statusBanner = "已为\(name)选择「\(url.lastPathComponent)」（尚未启用）"
            }
        }
    }
}
