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

    enum SettingsTab: String, CaseIterable, Identifiable {
        case wallpaper, mode, displays, general, diagnostics, about
        var id: String { rawValue }
        var title: String {
            switch self {
            case .wallpaper: return "壁纸"
            case .mode: return "模式"
            case .displays: return "显示器"
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
                displaysPage.tabItem { Label("显示器", systemImage: "display.2") }.tag(SettingsTab.displays)
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
                Text("「选图」只准备资源；「启用壁纸」才决定是否铺到桌面。停用不会删除已选图片。")
                    .font(.caption)
            }

            Section {
                Toggle(
                    "按显示器分别设置",
                    isOn: Binding(
                        get: { configStore.config.perDisplayEnabled },
                        set: { enabled in
                            configStore.update { $0.perDisplayEnabled = enabled }
                            statusBanner = enabled
                                ? "已开启分屏：请在下方为每块屏幕选图（可先不启用）"
                                : "已关闭分屏，将使用全局图片"
                        }
                    )
                )
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

                        if configStore.config.wallpaperEnabled, canApplyWallpaper {
                            Button("更新到桌面") {
                                statusBanner = "正在更新到桌面…"
                                modeEngine.updateDesktopAsync()
                            }
                            .disabled(modeEngine.isBusy)
                        } else if configStore.config.imagePath != nil, !configStore.config.wallpaperEnabled {
                            Text("已选图，打开上方「启用壁纸」后才会铺到桌面")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }

                        if configStore.config.perDisplayEnabled {
                            Text("未单独选图的屏幕会使用这张兜底图。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("缩放") {
                Picker("策略", selection: binding(\.scaleMode)) {
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
                            }
                        )
                    )
                    .disabled(modeEngine.isBusy)
                }
                if configStore.config.wallpaperEnabled {
                    Button("按当前缩放更新到桌面") {
                        statusBanner = "正在更新到桌面…"
                        modeEngine.updateDesktopAsync()
                    }
                    .disabled(modeEngine.isBusy || !canApplyWallpaper)
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
            return "先在下方选择图片；选图不会改变桌面。"
        }
        if configStore.config.wallpaperEnabled {
            return "已启用。改图或改缩放后，可点「更新到桌面」。关闭开关即可停用（不必删图）。"
        }
        return "图片已就绪。打开「启用壁纸」后才会铺到桌面。"
    }

    private func displayPickerRow(_ display: DisplayInfo) -> some View {
        let path = effectivePath(for: display.id)
        return HStack(alignment: .top, spacing: 12) {
            DisplayThumbnail(path: path)
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

                Text(shortPathLabel(for: display.id))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack {
                    Button("选择图片…") {
                        pickImage(for: display.id)
                    }
                    .disabled(modeEngine.isBusy)

                    if configStore.config.perDisplayMap[display.id] != nil {
                        Button("改用全局图") {
                            configStore.update { $0.perDisplayMap[display.id] = nil }
                            statusBanner = "\(display.localizedName) 已改为使用全局图（尚未更新桌面）"
                        }
                        .disabled(modeEngine.isBusy)

                        Button("移除", role: .destructive) {
                            clearDisplayImage(displayID: display.id, displayName: display.localizedName)
                        }
                        .disabled(modeEngine.isBusy)
                    }

                    if configStore.config.wallpaperEnabled, canApplyWallpaper {
                        Button("更新到桌面") {
                            statusBanner = "正在更新到桌面…"
                            modeEngine.updateDesktopAsync()
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
        if let path = configStore.config.perDisplayMap[displayID], !path.isEmpty {
            let name = URL(fileURLWithPath: path).lastPathComponent
            return configStore.config.wallpaperEnabled ? "已选：\(name)" : "已选：\(name)（尚未启用）"
        }
        if let global = configStore.config.imagePath {
            return "未单独选图 → 全局：\(URL(fileURLWithPath: global).lastPathComponent)"
        }
        return "尚未选图"
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
        autoDisableIfNoImageLeft()
    }

    private func clearDisplayImage(displayID: String, displayName: String) {
        let old = configStore.config.perDisplayMap[displayID]
        configStore.update { $0.perDisplayMap.removeValue(forKey: displayID) }
        if let old { ImagePipeline.invalidate(path: old) }
        statusBanner = "已移除 \(displayName) 的分屏图片"
        autoDisableIfNoImageLeft()
    }

    private func clearAllImages() {
        let oldGlobal = configStore.config.imagePath
        let oldMap = configStore.config.perDisplayMap
        configStore.update {
            $0.imagePath = nil
            $0.perDisplayMap = [:]
        }
        ImagePipeline.invalidateCache()
        if let oldGlobal { ImagePipeline.invalidate(path: oldGlobal) }
        for path in oldMap.values { ImagePipeline.invalidate(path: path) }
        previewImage = nil
        statusBanner = "已清除全部已选壁纸"
        autoDisableIfNoImageLeft(force: true)
    }

    private func autoDisableIfNoImageLeft(force: Bool = false) {
        let noImage = force || !canApplyWallpaper
        guard noImage else { return }
        if configStore.config.wallpaperEnabled || modeEngine.overlay.isActive || modeEngine.activeMode != nil {
            modeEngine.disableWallpaperAsync()
            statusBanner = (statusBanner ?? "") + "；已自动停用"
        }
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

    // MARK: - Displays

    private var displaysPage: some View {
        Form {
            if !configStore.config.perDisplayEnabled {
                Section {
                    Text("当前未开启「按显示器分别设置」。打开下方开关，或回壁纸页开启。")
                        .foregroundStyle(.secondary)
                    Toggle(
                        "启用分屏设置",
                        isOn: Binding(
                            get: { configStore.config.perDisplayEnabled },
                            set: { enabled in
                                configStore.update { $0.perDisplayEnabled = enabled }
                                statusBanner = enabled ? "已启用分屏，可为每块屏幕选择图片" : "已关闭分屏"
                            }
                        )
                    )
                }
            }

            if let tip = displayRegistry.lastChangeMessage {
                Section {
                    Text(tip).foregroundStyle(.orange)
                }
            }

            Section("显示器") {
                ForEach(displayRegistry.displays) { display in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(display.localizedName).font(.headline)
                            if display.isMain {
                                Text("主屏")
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .background(.quaternary)
                                    .clipShape(Capsule())
                            }
                            Spacer()
                            Text(display.resolutionDescription).foregroundStyle(.secondary)
                        }
                        Text("ID: \(display.id)").font(.caption2).foregroundStyle(.secondary)
                        Text(displayImageDescription(for: display.id))
                            .font(.caption)
                            .lineLimit(2)
                        HStack {
                            Button("选择图片…") {
                                pickImage(for: display.id)
                            }
                            .disabled(modeEngine.isBusy)

                            Button("使用全局图") {
                                configStore.update { $0.perDisplayMap[display.id] = nil }
                                statusBanner = "\(display.localizedName) 将使用全局图"
                            }
                            .disabled(modeEngine.isBusy)

                            Button("清除", role: .destructive) {
                                configStore.update { $0.perDisplayMap.removeValue(forKey: display.id) }
                                statusBanner = "已清除 \(display.localizedName) 的分屏图片"
                            }
                            .disabled(modeEngine.isBusy)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                Button("刷新显示器列表") {
                    displayRegistry.refresh()
                    statusBanner = "已刷新显示器列表（\(displayRegistry.displays.count) 块）"
                }
                if configStore.config.wallpaperEnabled {
                    Button("更新分屏配置到桌面") {
                        statusBanner = "正在更新到桌面…"
                        modeEngine.updateDesktopAsync()
                    }
                    .disabled(modeEngine.isBusy || !canApplyWallpaper)
                } else {
                    Text("选图后请到「壁纸」页打开「启用壁纸」。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("主路径在「壁纸」页：选图与启用分离；本页用于查看/调整分屏映射。")
                    .font(.caption)
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Ink Paper").font(.largeTitle.bold())
            Text("macOS 静态壁纸工具")
            Text("版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")")
                .foregroundStyle(.secondary)
            Text("构建 \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")")
                .foregroundStyle(.secondary)
            Text("支持 macOS 13+ · Swift + AppKit/SwiftUI")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
    }

    // MARK: - Helpers

    private func binding<T>(_ keyPath: WritableKeyPath<AppConfig, T>) -> Binding<T> {
        Binding(
            get: { configStore.config[keyPath: keyPath] },
            set: { value in configStore.update { $0[keyPath: keyPath] = value } }
        )
    }

    private func displayImageDescription(for displayID: String) -> String {
        if let path = configStore.config.perDisplayMap[displayID], !path.isEmpty {
            return path
        }
        if configStore.config.perDisplayEnabled {
            return configStore.config.imagePath.map { "回退全局图：\($0)" } ?? "未设置（也无全局图）"
        }
        return configStore.config.imagePath.map { "使用全局图：\($0)" } ?? "未设置"
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
                statusBanner = "已选择「\(name)」。可点「更新到桌面」"
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
            }
            ImagePipeline.invalidate(path: url.path)
            if configStore.config.wallpaperEnabled {
                statusBanner = "已为\(name)选择「\(url.lastPathComponent)」。可点行内「更新到桌面」"
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
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
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
    }

    private func load() {
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
