import AppKit
import Foundation

enum WallpaperMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case overlay

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "系统壁纸"
        case .overlay: return "底层窗口"
        }
    }
}

enum PreferredMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case system
    case overlay

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "自动"
        case .system: return "强制系统壁纸"
        case .overlay: return "强制底层窗口"
        }
    }
}

enum ScaleMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case fill
    case fit
    case stretch
    case center

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fill: return "填充（可能裁剪）"
        case .fit: return "适应（可能留边）"
        case .stretch: return "拉伸"
        case .center: return "居中"
        }
    }
}

struct RGBAColor: Codable, Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let black = RGBAColor(red: 0, green: 0, blue: 0, alpha: 1)

    var nsColor: NSColor {
        NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(nsColor: NSColor) {
        let c = nsColor.usingColorSpace(.deviceRGB) ?? nsColor
        red = Double(c.redComponent)
        green = Double(c.greenComponent)
        blue = Double(c.blueComponent)
        alpha = Double(c.alphaComponent)
    }
}

struct HealthCheckSummary: Codable, Equatable, Sendable {
    var passCount: Int
    var warnCount: Int
    var failCount: Int
    var lines: [String]

    static let empty = HealthCheckSummary(passCount: 0, warnCount: 0, failCount: 0, lines: [])
}

struct AppConfig: Codable, Equatable, Sendable {
    // General
    var launchAtLogin: Bool
    var showMenuBarExtra: Bool
    var openConfigOnLaunch: Bool
    var language: String
    var lastMode: WallpaperMode
    var preferredMode: PreferredMode
    var backupSystemWallpaperBeforeSwitch: Bool

    // Wallpaper
    var wallpaperEnabled: Bool
    var imagePath: String?
    var perDisplayEnabled: Bool
    var perDisplayMap: [String: String]
    /// 显式「仅原生壁纸」的显示器；不删 `perDisplayMap` 里的原路径，便于恢复覆盖。
    var perDisplayNativeIDs: Set<String>
    var scaleMode: ScaleMode
    var fitBackgroundColor: RGBAColor
    var applyToAllSpaces: Bool

    // Overlay
    var overlayEnabled: Bool
    var ignoreMouseEvents: Bool
    var restoreOnDisplayChange: Bool
    var hideOnAppQuit: Bool

    // Health
    var checkOnLaunch: Bool
    var autoFallbackToOverlay: Bool
    var notifyOnFallback: Bool
    var lastCheckAt: Date?
    var lastCheckReport: HealthCheckSummary

    // Limits
    var maxImageBytes: Int64
    var maxImageDimension: Int

    enum CodingKeys: String, CodingKey {
        case launchAtLogin, showMenuBarExtra, openConfigOnLaunch, language
        case lastMode, preferredMode, backupSystemWallpaperBeforeSwitch
        case wallpaperEnabled, imagePath, perDisplayEnabled, perDisplayMap, perDisplayNativeIDs
        case scaleMode, fitBackgroundColor, applyToAllSpaces
        case overlayEnabled, ignoreMouseEvents, restoreOnDisplayChange, hideOnAppQuit
        case checkOnLaunch, autoFallbackToOverlay, notifyOnFallback, lastCheckAt, lastCheckReport
        case maxImageBytes, maxImageDimension
    }

    init(
        launchAtLogin: Bool,
        showMenuBarExtra: Bool,
        openConfigOnLaunch: Bool,
        language: String,
        lastMode: WallpaperMode,
        preferredMode: PreferredMode,
        backupSystemWallpaperBeforeSwitch: Bool,
        wallpaperEnabled: Bool,
        imagePath: String?,
        perDisplayEnabled: Bool,
        perDisplayMap: [String: String],
        perDisplayNativeIDs: Set<String>,
        scaleMode: ScaleMode,
        fitBackgroundColor: RGBAColor,
        applyToAllSpaces: Bool,
        overlayEnabled: Bool,
        ignoreMouseEvents: Bool,
        restoreOnDisplayChange: Bool,
        hideOnAppQuit: Bool,
        checkOnLaunch: Bool,
        autoFallbackToOverlay: Bool,
        notifyOnFallback: Bool,
        lastCheckAt: Date?,
        lastCheckReport: HealthCheckSummary,
        maxImageBytes: Int64,
        maxImageDimension: Int
    ) {
        self.launchAtLogin = launchAtLogin
        self.showMenuBarExtra = showMenuBarExtra
        self.openConfigOnLaunch = openConfigOnLaunch
        self.language = language
        self.lastMode = lastMode
        self.preferredMode = preferredMode
        self.backupSystemWallpaperBeforeSwitch = backupSystemWallpaperBeforeSwitch
        self.wallpaperEnabled = wallpaperEnabled
        self.imagePath = imagePath
        self.perDisplayEnabled = perDisplayEnabled
        self.perDisplayMap = perDisplayMap
        self.perDisplayNativeIDs = perDisplayNativeIDs
        self.scaleMode = scaleMode
        self.fitBackgroundColor = fitBackgroundColor
        self.applyToAllSpaces = applyToAllSpaces
        self.overlayEnabled = overlayEnabled
        self.ignoreMouseEvents = ignoreMouseEvents
        self.restoreOnDisplayChange = restoreOnDisplayChange
        self.hideOnAppQuit = hideOnAppQuit
        self.checkOnLaunch = checkOnLaunch
        self.autoFallbackToOverlay = autoFallbackToOverlay
        self.notifyOnFallback = notifyOnFallback
        self.lastCheckAt = lastCheckAt
        self.lastCheckReport = lastCheckReport
        self.maxImageBytes = maxImageBytes
        self.maxImageDimension = maxImageDimension
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppConfig.default
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
        showMenuBarExtra = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarExtra) ?? defaults.showMenuBarExtra
        openConfigOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .openConfigOnLaunch) ?? defaults.openConfigOnLaunch
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? defaults.language
        lastMode = try c.decodeIfPresent(WallpaperMode.self, forKey: .lastMode) ?? defaults.lastMode
        preferredMode = try c.decodeIfPresent(PreferredMode.self, forKey: .preferredMode) ?? defaults.preferredMode
        backupSystemWallpaperBeforeSwitch = try c.decodeIfPresent(Bool.self, forKey: .backupSystemWallpaperBeforeSwitch) ?? defaults.backupSystemWallpaperBeforeSwitch
        // 旧配置无此字段：若曾成功跑过 overlay，视为已启用，避免升级后桌面突然空白。
        let decodedEnabled = try c.decodeIfPresent(Bool.self, forKey: .wallpaperEnabled)
        let decodedOverlay = try c.decodeIfPresent(Bool.self, forKey: .overlayEnabled) ?? false
        wallpaperEnabled = decodedEnabled ?? decodedOverlay
        imagePath = try c.decodeIfPresent(String.self, forKey: .imagePath)
        perDisplayEnabled = try c.decodeIfPresent(Bool.self, forKey: .perDisplayEnabled) ?? defaults.perDisplayEnabled
        var map = try c.decodeIfPresent([String: String].self, forKey: .perDisplayMap) ?? [:]
        var nativeIDs = Set(try c.decodeIfPresent([String].self, forKey: .perDisplayNativeIDs) ?? [])
        // 迁移旧哨兵：空字符串曾表示「仅原生」。
        for (id, path) in map where path.isEmpty {
            nativeIDs.insert(id)
        }
        map = map.filter { !$0.value.isEmpty }
        perDisplayMap = map
        perDisplayNativeIDs = nativeIDs
        scaleMode = try c.decodeIfPresent(ScaleMode.self, forKey: .scaleMode) ?? defaults.scaleMode
        fitBackgroundColor = try c.decodeIfPresent(RGBAColor.self, forKey: .fitBackgroundColor) ?? defaults.fitBackgroundColor
        applyToAllSpaces = try c.decodeIfPresent(Bool.self, forKey: .applyToAllSpaces) ?? defaults.applyToAllSpaces
        overlayEnabled = decodedOverlay
        ignoreMouseEvents = try c.decodeIfPresent(Bool.self, forKey: .ignoreMouseEvents) ?? true
        restoreOnDisplayChange = try c.decodeIfPresent(Bool.self, forKey: .restoreOnDisplayChange) ?? defaults.restoreOnDisplayChange
        hideOnAppQuit = try c.decodeIfPresent(Bool.self, forKey: .hideOnAppQuit) ?? true
        checkOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .checkOnLaunch) ?? defaults.checkOnLaunch
        autoFallbackToOverlay = try c.decodeIfPresent(Bool.self, forKey: .autoFallbackToOverlay) ?? defaults.autoFallbackToOverlay
        notifyOnFallback = try c.decodeIfPresent(Bool.self, forKey: .notifyOnFallback) ?? defaults.notifyOnFallback
        lastCheckAt = try c.decodeIfPresent(Date.self, forKey: .lastCheckAt)
        lastCheckReport = try c.decodeIfPresent(HealthCheckSummary.self, forKey: .lastCheckReport) ?? .empty
        maxImageBytes = try c.decodeIfPresent(Int64.self, forKey: .maxImageBytes) ?? defaults.maxImageBytes
        maxImageDimension = try c.decodeIfPresent(Int.self, forKey: .maxImageDimension) ?? defaults.maxImageDimension
    }

    static let `default` = AppConfig(
        launchAtLogin: false,
        showMenuBarExtra: true,
        openConfigOnLaunch: false,
        language: "system",
        lastMode: .system,
        preferredMode: .auto,
        backupSystemWallpaperBeforeSwitch: true,
        wallpaperEnabled: false,
        imagePath: nil,
        perDisplayEnabled: false,
        perDisplayMap: [:],
        perDisplayNativeIDs: [],
        scaleMode: .fill,
        fitBackgroundColor: .black,
        applyToAllSpaces: true,
        overlayEnabled: false,
        ignoreMouseEvents: true,
        restoreOnDisplayChange: true,
        hideOnAppQuit: true,
        checkOnLaunch: true,
        autoFallbackToOverlay: true,
        notifyOnFallback: true,
        lastCheckAt: nil,
        lastCheckReport: .empty,
        maxImageBytes: 50 * 1024 * 1024,
        maxImageDimension: 16384
    )

    /// `perDisplayMap` 只存真实路径；「仅原生」用 `perDisplayNativeIDs`（兼容旧空字符串哨兵）。
    static let perDisplayNativeSentinel = ""

    /// 分屏开启且该屏显式标记为「仅原生壁纸」。
    func usesNativeWallpaperOnly(forDisplayID displayID: String) -> Bool {
        guard perDisplayEnabled else { return false }
        if perDisplayNativeIDs.contains(displayID) { return true }
        if let path = perDisplayMap[displayID], path.isEmpty { return true }
        return false
    }

    /// 解析该屏实际要用的图片路径；原生-only 返回 `nil`（不覆盖该屏）。
    func imagePath(forDisplayID displayID: String) -> String? {
        if perDisplayEnabled {
            if usesNativeWallpaperOnly(forDisplayID: displayID) { return nil }
            if let path = perDisplayMap[displayID], !path.isEmpty { return path }
            return imagePath
        }
        return imagePath
    }

    /// 是否至少有一块屏当前会铺到 Ink Paper 图（与是否启用无关）。
    func hasUsableWallpaperImage(displayIDs: [String]) -> Bool {
        if perDisplayEnabled {
            return displayIDs.contains { imagePath(forDisplayID: $0) != nil }
        }
        if let imagePath, !imagePath.isEmpty { return true }
        return false
    }

    /// 是否仍保留可选图资源（含被「仅原生」暂时不用的分屏路径 / 全局图）。
    func hasWallpaperImageAssets() -> Bool {
        if let imagePath, !imagePath.isEmpty { return true }
        return perDisplayMap.values.contains { !$0.isEmpty }
    }
}
