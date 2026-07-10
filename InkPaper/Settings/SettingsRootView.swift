import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsRootView: View {
    @ObservedObject var configStore: ConfigStore
    @ObservedObject var modeEngine: ModeEngine
    @ObservedObject var displayRegistry: DisplayRegistry

    @State private var selectedTab: SettingsTab = .wallpaper
    @State private var healthItems: [CheckItemResult] = []
    @State private var healthCheckedAt: Date?
    @State private var alertMessage: String?
    @State private var previewImage: NSImage?
    @State private var statusBanner: String?
    @State private var reapplyDebounceTask: Task<Void, Never>?

    enum SettingsTab: String, CaseIterable, Identifiable {
        case wallpaper, mode, general, diagnostics, about
        var id: String { rawValue }
        var title: String {
            switch self {
            case .wallpaper: return "壁纸"
            case .mode: return "模式"
            case .general: return "通用"
            case .diagnostics: return "诊断"
            case .about: return "关于"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if modeEngine.isBusy || statusBanner != nil || modeEngine.statusMessage != nil || modeEngine.lastError != nil {
                statusBar
            }

            TabView(selection: $selectedTab) {
                wallpaperPage.tabItem { Label("壁纸", systemImage: "photo") }.tag(SettingsTab.wallpaper)
                modePage.tabItem { Label("模式", systemImage: "switch.2") }.tag(SettingsTab.mode)
                generalPage.tabItem { Label("通用", systemImage: "gearshape") }.tag(SettingsTab.general)
                diagnosticsPage.tabItem { Label("诊断", systemImage: "stethoscope") }.tag(SettingsTab.diagnostics)
                aboutPage.tabItem { Label("关于", systemImage: "info.circle") }.tag(SettingsTab.about)
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
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("好", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
        .onAppear { reloadPreview() }
        .onChange(of: configStore.config.imagePath) { _ in reloadPreview() }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if modeEngine.isBusy {
                ProgressView().controlSize(.small)
            }
            Text(modeEngine.lastError ?? statusBanner ?? modeEngine.statusMessage ?? "")
                .font(.caption)
                .foregroundStyle(modeEngine.lastError == nil ? Color.secondary : Color.red)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Wallpaper

    private var wallpaperPage: some View {
        Form {
            Section {
                enableWallpaperControls
            } header: {
                Text("启用")
            } footer: {
                Text("打开「启用壁纸」后桌面立即生效；之后选图、换图会直接更新桌面。停用不会删除已选图片。")
                    .font(.caption)
            }

            Section {
                Toggle(
                    "按显示器分别设置",
                    isOn: Binding(
                        get: { configStore.config.perDisplayEnabled },
                        set: { enabled in
                            configStore.update { $0.perDisplayEnabled = enabled }
                            if enabled {
                                statusBanner = "已开启分屏：可为每块屏幕选图，或指定仅用原生壁纸"
                            } else {
                                statusBanner = "已关闭分屏，将使用全局图片"
                            }
                            reapplyIfEnabled()
                        }
                    )
                )
            } footer: {
                Text("开启后可为每块屏单独选图；也可让某块屏不覆盖，仅保留系统原生壁纸。")
                    .font(.caption)
            }

            if let tip = displayRegistry.lastChangeMessage {
                Section {
                    Text(tip).foregroundStyle(.orange)
                }
            }

            if configStore.config.perDisplayEnabled {
                Section("各显示器壁纸") {
                    if displayRegistry.displays.isEmpty {
                        Text("未检测到显示器").foregroundStyle(.secondary)
                    } else {
                        ForEach(displayRegistry.displays) { display in
                            displayPickerRow(display)
                        }
                    }
                    Button("刷新显示器列表") {
                        displayRegistry.refresh()
                        statusBanner = "已刷新显示器列表（\(displayRegistry.displays.count) 块）"
                    }
                    .disabled(modeEngine.isBusy)
                }
            }

            Section(configStore.config.perDisplayEnabled ? "全局兜底图片" : "全局图片") {
                HStack(alignment: .top, spacing: 16) {
                    thumbnailBox(image: previewImage, emptyText: configStore.config.imagePath == nil ? "无预览" : "加载中…")
                        .frame(width: 220, height: 140)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(selectionCaption(path: configStore.config.imagePath))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)

                        HStack {
                            Button(configStore.config.perDisplayEnabled ? "选择兜底图…" : "选择图片…") {
                                pickGlobalImage()
                            }
                            .disabled(modeEngine.isBusy)

                            if configStore.config.imagePath != nil {
                                Button("移除", role: .destructive) {
                                    clearGlobalImage()
                                }
                                .disabled(modeEngine.isBusy)
                            }
                        }

                        if configStore.config.imagePath != nil, !configStore.config.wallpaperEnabled {
                            Text("已选图，打开上方「启用壁纸」后才会铺到桌面")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }

                        if configStore.config.perDisplayEnabled {
                            Text("未单独选图的屏幕会使用这张兜底图；标记为「仅原生」的屏幕不会使用。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("缩放") {
                Picker(
                    "策略",
                    selection: Binding(
                        get: { configStore.config.scaleMode },
                        set: { mode in
                            configStore.update { $0.scaleMode = mode }
                            statusBanner = "缩放已改为「\(mode.displayName)」"
                            reapplyIfEnabled()
                        }
                    )
                ) {
                    ForEach(ScaleMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .disabled(modeEngine.isBusy)
                if configStore.config.scaleMode == .fit {
                    ColorPicker(
                        "留边颜色",
                        selection: Binding(
                            get: { Color(nsColor: configStore.config.fitBackgroundColor.nsColor) },
                            set: { color in
                                configStore.update {
                                    $0.fitBackgroundColor = RGBAColor(nsColor: NSColor(color))
                                }
                                statusBanner = "已更新留边颜色"
                                reapplyIfEnabled(debounceMilliseconds: 400)
                            }
                        )
                    )
                    .disabled(modeEngine.isBusy)
                }
            }

            if hasAnySelectedImage {
                Section {
                    Button("清除全部已选壁纸", role: .destructive) {
                        clearAllImages()
                    }
                    .disabled(modeEngine.isBusy)
                } footer: {
                    Text("清除图片后会自动停用。若只想暂时不显示，请关闭上方「启用壁纸」。")
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }

    private var enableWallpaperControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(
                "启用壁纸",
                isOn: Binding(
                    get: { configStore.config.wallpaperEnabled },
                    set: { enabled in
                        if enabled {
                            guard canApplyWallpaper else {
                                alertMessage = "请先选择至少一张壁纸图片，再启用"
                                return
                            }
                            statusBanner = "正在启用壁纸…"
                            modeEngine.enableWallpaperAsync()
                        } else {
                            statusBanner = "正在停用壁纸…"
                            modeEngine.disableWallpaperAsync()
                        }
                    }
                )
            )
            .disabled(modeEngine.isBusy || (!configStore.config.wallpaperEnabled && !canApplyWallpaper))

            HStack(spacing: 8) {
                statusBadge
                if modeEngine.isBusy {
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
        if modeEngine.isBusy {
            text = "处理中"
            color = .orange
        } else if modeEngine.lastError != nil, configStore.config.wallpaperEnabled {
            text = "失败"
            color = .red
        } else if configStore.config.wallpaperEnabled, let mode = modeEngine.activeMode {
            text = "运行中 · \(mode.displayName)"
            color = .green
        } else if configStore.config.wallpaperEnabled {
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
        if configStore.config.wallpaperEnabled {
            return "已启用。选图、换图、改缩放会直接更新桌面。关闭开关即可停用（不必删图）。"
        }
        return "图片已就绪。打开「启用壁纸」后才会铺到桌面。"
    }

    private func displayPickerRow(_ display: DisplayInfo) -> some View {
        let path = effectivePath(for: display.id)
        let isNative = configStore.config.usesNativeWallpaperOnly(forDisplayID: display.id)
        let hasCustom = {
            if let p = configStore.config.perDisplayMap[display.id], !p.isEmpty { return true }
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
                    .disabled(modeEngine.isBusy)

                    if isNative {
                        Button("恢复覆盖") {
                            restoreCoverage(displayID: display.id, displayName: display.localizedName)
                        }
                        .disabled(modeEngine.isBusy)
                    } else if hasCustom {
                        Button("改用兜底图") {
                            useGlobalFallback(displayID: display.id, displayName: display.localizedName)
                        }
                        .disabled(modeEngine.isBusy)
                    }

                    if !isNative {
                        Button("仅原生壁纸", role: .destructive) {
                            setNativeOnly(displayID: display.id, displayName: display.localizedName)
                        }
                        .disabled(modeEngine.isBusy)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var canApplyWallpaper: Bool {
        configStore.config.hasUsableWallpaperImage(displayIDs: displayRegistry.displays.map(\.id))
    }

    private var hasAnySelectedImage: Bool {
        if configStore.config.imagePath != nil { return true }
        return configStore.config.perDisplayMap.values.contains { !$0.isEmpty }
    }

    private func effectivePath(for displayID: String) -> String? {
        configStore.config.imagePath(forDisplayID: displayID)
    }

    private func selectionCaption(path: String?) -> String {
        guard let path else { return "未选择" }
        let name = URL(fileURLWithPath: path).lastPathComponent
        if configStore.config.wallpaperEnabled {
            return "已选：\(name)"
        }
        return "已选：\(name)（尚未启用）"
    }

    private func shortPathLabel(for displayID: String) -> String {
        if configStore.config.usesNativeWallpaperOnly(forDisplayID: displayID) {
            if let path = configStore.config.perDisplayMap[displayID], !path.isEmpty {
                let name = URL(fileURLWithPath: path).lastPathComponent
                return "仅原生壁纸（已保留分屏图：\(name)）"
            }
            if let global = configStore.config.imagePath {
                return "仅原生壁纸（恢复后可用兜底：\(URL(fileURLWithPath: global).lastPathComponent)）"
            }
            return "仅原生壁纸（不覆盖）"
        }
        if let path = configStore.config.perDisplayMap[displayID], !path.isEmpty {
            let name = URL(fileURLWithPath: path).lastPathComponent
            return configStore.config.wallpaperEnabled ? "已选：\(name)" : "已选：\(name)（尚未启用）"
        }
        if let global = configStore.config.imagePath {
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

    private func clearGlobalImage() {
        let old = configStore.config.imagePath
        configStore.update { $0.imagePath = nil }
        if let old { ImagePipeline.invalidate(path: old) }
        previewImage = nil
        statusBanner = "已移除全局图片"
        if configStore.config.wallpaperEnabled, canApplyWallpaper {
            reapplyIfEnabled()
        } else {
            autoDisableIfNoImageLeft()
        }
    }

    /// 该屏改回使用全局兜底图（清除分屏图与「仅原生」标记）。
    private func useGlobalFallback(displayID: String, displayName: String) {
        let old = configStore.config.perDisplayMap[displayID]
        configStore.update {
            $0.perDisplayNativeIDs.remove(displayID)
            $0.perDisplayMap.removeValue(forKey: displayID)
        }
        if let old, !old.isEmpty { ImagePipeline.invalidate(path: old) }
        guard configStore.config.imagePath != nil else {
            statusBanner = "\(displayName) 已改回兜底，但尚未设置兜底图"
            alertMessage = "请先在下方选择全局兜底图片"
            autoDisableIfNoImageLeft()
            return
        }
        statusBanner = "\(displayName) 已改为使用兜底图"
        applyDesktopAfterConfigChange()
    }

    /// 取消「仅原生」，恢复该屏覆盖（优先分屏图，否则兜底图）。
    private func restoreCoverage(displayID: String, displayName: String) {
        configStore.update {
            $0.perDisplayNativeIDs.remove(displayID)
            // 清掉旧空字符串哨兵
            if let path = $0.perDisplayMap[displayID], path.isEmpty {
                $0.perDisplayMap.removeValue(forKey: displayID)
            }
        }
        let path = configStore.config.imagePath(forDisplayID: displayID)
        guard path != nil else {
            statusBanner = "\(displayName) 已取消仅原生，但没有可铺的图片"
            alertMessage = "请为该屏选择图片，或先设置全局兜底图"
            autoDisableIfNoImageLeft()
            return
        }
        statusBanner = "\(displayName) 已恢复覆盖"
        applyDesktopAfterConfigChange()
    }

    /// 该屏不铺 Ink Paper，仅保留系统原生壁纸；保留已选分屏路径以便恢复。
    private func setNativeOnly(displayID: String, displayName: String) {
        configStore.update {
            $0.perDisplayNativeIDs.insert(displayID)
            // 清掉旧空字符串哨兵，避免与 nativeIDs 重复语义
            if let path = $0.perDisplayMap[displayID], path.isEmpty {
                $0.perDisplayMap.removeValue(forKey: displayID)
            }
        }
        statusBanner = "\(displayName) 已设为仅原生壁纸（不覆盖）"
        if configStore.config.wallpaperEnabled {
            // 即使当前已无任何覆盖屏，也要重铺以拆掉该屏窗口；不因此自动停用。
            modeEngine.updateDesktopAsync()
        }
    }

    private func clearAllImages() {
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
        previewImage = nil
        statusBanner = "已清除全部已选壁纸"
        autoDisableIfNoImageLeft(force: true)
    }

    private func autoDisableIfNoImageLeft(force: Bool = false) {
        let noAssets = force || !configStore.config.hasWallpaperImageAssets()
        guard noAssets else { return }
        if configStore.config.wallpaperEnabled || modeEngine.overlay.isActive || modeEngine.activeMode != nil {
            modeEngine.disableWallpaperAsync()
            statusBanner = (statusBanner ?? "") + "；已自动停用"
        }
    }

    /// 配置变更后：已启用则重铺；未启用但已有可铺图则保持未启用（由用户开开关）。
    private func applyDesktopAfterConfigChange() {
        if configStore.config.wallpaperEnabled {
            if canApplyWallpaper {
                modeEngine.updateDesktopAsync()
            } else if configStore.config.hasWallpaperImageAssets() {
                // 仍启用但暂时全原生等：同步拆窗/重铺
                modeEngine.updateDesktopAsync()
            } else {
                autoDisableIfNoImageLeft()
            }
        } else if canApplyWallpaper {
            // 若先前因全原生被误停用，恢复覆盖时应重新启用
            statusBanner = (statusBanner ?? "") + "，正在重新启用…"
            modeEngine.enableWallpaperAsync()
        }
    }

    /// 已启用时把当前配置立刻重铺到桌面（选图/换图/改缩放等直接生效）。
    private func reapplyIfEnabled(debounceMilliseconds: UInt64 = 0) {
        guard configStore.config.wallpaperEnabled else { return }
        guard canApplyWallpaper || configStore.config.hasWallpaperImageAssets() else { return }
        if debounceMilliseconds > 0 {
            reapplyDebounceTask?.cancel()
            reapplyDebounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: debounceMilliseconds * 1_000_000)
                guard !Task.isCancelled else { return }
                guard configStore.config.wallpaperEnabled else { return }
                modeEngine.updateDesktopAsync()
            }
            return
        }
        modeEngine.updateDesktopAsync()
    }

    // MARK: - Mode

    private var modePage: some View {
        Form {
            Section("状态") {
                LabeledContent("当前模式") {
                    Text(modeEngine.activeMode?.displayName ?? "未启用")
                }
                LabeledContent("处理状态") {
                    Text(modeEngine.isBusy ? "处理中" : "空闲")
                }
                let probe = modeEngine.systemWallpaper.lastLockProbe
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

            Section("偏好") {
                Picker(
                    "偏好模式",
                    selection: Binding(
                        get: { configStore.config.preferredMode },
                        set: { value in
                            configStore.update { $0.preferredMode = value }
                            statusBanner = "偏好已改为「\(value.displayName)」，点击下方按钮才会真正切换"
                        }
                    )
                ) {
                    ForEach(PreferredMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .disabled(modeEngine.isBusy)

                Toggle("系统壁纸失败时自动降级到底层窗口", isOn: binding(\.autoFallbackToOverlay))
                Toggle("降级时通知", isOn: binding(\.notifyOnFallback))
                Toggle("切换前备份系统壁纸", isOn: binding(\.backupSystemWallpaperBeforeSwitch))
                Toggle("底层窗口出现在所有 Space", isOn: binding(\.applyToAllSpaces))
            }

            Section("说明") {
                Text("「启用壁纸」在壁纸页顶部。本页切换模式会隐含启用。停用请回壁纸页关闭开关，无需删图。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("操作") {
                Button("按偏好立即应用（并启用）") {
                    statusBanner = "正在按偏好应用…"
                    modeEngine.applyPreferredModeAsync()
                }
                .disabled(modeEngine.isBusy || !canApplyWallpaper)

                Button("切换到系统壁纸（并启用）") {
                    statusBanner = "正在切换到系统壁纸…"
                    modeEngine.switchToAsync(.system)
                }
                .disabled(modeEngine.isBusy || !canApplyWallpaper)

                Button("切换到底层窗口（并启用）") {
                    statusBanner = "正在切换到底层窗口…"
                    modeEngine.switchToAsync(.overlay)
                }
                .disabled(modeEngine.isBusy || !canApplyWallpaper)

                if configStore.config.wallpaperEnabled {
                    Button("停用壁纸", role: .destructive) {
                        statusBanner = "正在停用壁纸…"
                        modeEngine.disableWallpaperAsync()
                    }
                    .disabled(modeEngine.isBusy)
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }

    // MARK: - General

    private var generalPage: some View {
        Form {
            Toggle("登录时启动", isOn: Binding(
                get: { configStore.config.launchAtLogin },
                set: { value in
                    configStore.update { $0.launchAtLogin = value }
                    configStore.applyLaunchAtLogin()
                    statusBanner = value ? "已开启登录启动" : "已关闭登录启动"
                }
            ))
            Toggle("显示菜单栏图标", isOn: binding(\.showMenuBarExtra))
            Toggle("启动时打开设置", isOn: binding(\.openConfigOnLaunch))
            Toggle("启动时健康检查", isOn: binding(\.checkOnLaunch))
            Toggle("显示器变化后重建底层窗口", isOn: binding(\.restoreOnDisplayChange))
        }
        .formStyle(.grouped)
        .padding(8)
        .disabled(modeEngine.isBusy)
    }

    // MARK: - Diagnostics

    private var diagnosticsPage: some View {
        Form {
            Section {
                HStack {
                    Button("运行检查") {
                        Task {
                            let report = await modeEngine.runHealthCheck(deep: false)
                            healthItems = report.items
                            healthCheckedAt = report.checkedAt
                            statusBanner = "检查完成：通过 \(report.passCount) / 警告 \(report.warnCount) / 失败 \(report.failCount)"
                        }
                    }
                    .disabled(modeEngine.isBusy)

                    Button("深度检查（可能闪屏）") {
                        Task {
                            let report = await modeEngine.runHealthCheck(deep: true)
                            healthItems = report.items
                            healthCheckedAt = report.checkedAt
                            statusBanner = "深度检查完成"
                        }
                    }
                    .disabled(modeEngine.isBusy)

                    Button("复制报告") {
                        Task {
                            let text: String
                            if healthItems.isEmpty {
                                text = await modeEngine.runHealthCheck(deep: false).textReport
                            } else {
                                text = HealthReport(items: healthItems, checkedAt: healthCheckedAt ?? Date()).textReport
                            }
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                            alertMessage = "报告已复制到剪贴板"
                        }
                    }
                }
                if let at = healthCheckedAt ?? configStore.config.lastCheckAt {
                    Text("上次检查：\(at.formatted())").font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("结果") {
                if healthItems.isEmpty {
                    if configStore.config.lastCheckReport.lines.isEmpty {
                        Text("尚未运行检查")
                    } else {
                        ForEach(configStore.config.lastCheckReport.lines, id: \.self) { line in
                            Text(line).font(.caption)
                        }
                    }
                } else {
                    ForEach(healthItems) { item in
                        HStack(alignment: .top) {
                            Circle()
                                .fill(item.severity == .pass ? Color.green : item.severity == .warn ? Color.orange : Color.red)
                                .frame(width: 8, height: 8)
                                .padding(.top, 6)
                            VStack(alignment: .leading) {
                                Text("\(item.id) · \(item.title)")
                                Text(item.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }

    // MARK: - About

    private var aboutPage: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

        return ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)

                    Text("Ink Paper")
                        .font(.title.bold())

                    Text("macOS 静态壁纸工具")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("版本 \(version)（\(build)）· 支持 macOS 13+")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

                Form {
                    Section {
                        LabeledContent("开源协议", value: "MIT License")
                        LabeledContent("项目主页") {
                            Link("github.com/suilang/ink-paper", destination: URL(string: "https://github.com/suilang/ink-paper")!)
                        }
                    } header: {
                        Text("信息")
                    }

                    Section {
                        VStack(spacing: 12) {
                            Text("如果本项目对您有帮助，欢迎请作者喝杯奶茶。")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)

                            Image("WeChatPay")
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .frame(width: 200, height: 196)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
                                .accessibilityLabel("微信赞赏码")

                            Text("微信扫码赞赏 · 仅用于本项目维护与开发")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                    } header: {
                        Text("赞助")
                    }
                }
                .formStyle(.grouped)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Helpers

    private func binding<T>(_ keyPath: WritableKeyPath<AppConfig, T>) -> Binding<T> {
        Binding(
            get: { configStore.config[keyPath: keyPath] },
            set: { value in configStore.update { $0[keyPath: keyPath] = value } }
        )
    }

    private func reloadPreview() {
        let path = configStore.config.imagePath
        guard let path else {
            previewImage = nil
            return
        }
        // 缩略图异步加载，避免切回壁纸 Tab 时主线程读大图卡死。
        Task.detached(priority: .utility) {
            let image = ImagePipeline.loadThumbnail(path: path, maxPixelSize: 512)
            await MainActor.run {
                if configStore.config.imagePath == path {
                    previewImage = image
                }
            }
        }
    }

    private func pickGlobalImage() {
        presentOpenPanel { url in
            configStore.update { $0.imagePath = url.path }
            ImagePipeline.invalidate(path: url.path)
            reloadPreview()
            let name = url.lastPathComponent
            if configStore.config.wallpaperEnabled {
                statusBanner = "已选择「\(name)」，正在应用到桌面…"
                reapplyIfEnabled()
            } else {
                statusBanner = "已选择「\(name)」（尚未启用）"
            }
        }
    }

    private func pickImage(for displayID: String) {
        presentOpenPanel { url in
            let name = displayRegistry.displays.first(where: { $0.id == displayID })?.localizedName ?? "该屏"
            configStore.update {
                $0.perDisplayEnabled = true
                $0.perDisplayMap[displayID] = url.path
                $0.perDisplayNativeIDs.remove(displayID)
            }
            ImagePipeline.invalidate(path: url.path)
            if configStore.config.wallpaperEnabled {
                statusBanner = "已为\(name)选择「\(url.lastPathComponent)」，正在应用到桌面…"
                reapplyIfEnabled()
            } else {
                statusBanner = "已为\(name)选择「\(url.lastPathComponent)」（尚未启用）"
            }
        }
    }

    private func presentOpenPanel(onPick: @escaping (URL) -> Void) {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = ImagePipeline.allowedContentTypes
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.title = "选择壁纸图片"
            panel.begin { response in
                guard response == .OK, let url = panel.url else {
                    statusBanner = "已取消选图"
                    return
                }
                onPick(url)
            }
        }
    }
}

// MARK: - Thumbnail

private struct DisplayThumbnail: View {
    let path: String?
    var nativeOnly: Bool = false
    @State private var image: NSImage?

    var body: some View {
        Group {
            if nativeOnly {
                Text("原生")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Text(path == nil ? "无图" : "…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .clipped()
        .onAppear { load() }
        .onChange(of: path) { _ in load() }
        .onChange(of: nativeOnly) { _ in
            if nativeOnly { image = nil }
        }
    }

    private func load() {
        if nativeOnly {
            image = nil
            return
        }
        guard let path else {
            image = nil
            return
        }
        Task.detached(priority: .utility) {
            let thumb = ImagePipeline.loadThumbnail(path: path, maxPixelSize: 256)
            await MainActor.run {
                image = thumb
            }
        }
    }
}
