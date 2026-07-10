import AppKit
import Foundation

struct WallpaperBackupEntry: Codable, Equatable {
    var displayID: String
    var path: String?
}

struct DesktopLockProbe: Equatable {
    var isLocked: Bool
    var reasons: [String]
    var overridePicturePath: String?
    var managedPreferencePaths: [String]

    var summary: String {
        if !isLocked {
            return "未检测到桌面壁纸托管锁定"
        }
        if reasons.isEmpty {
            return "检测到桌面壁纸被策略锁定"
        }
        return reasons.joined(separator: "；")
    }

    static let unlocked = DesktopLockProbe(
        isLocked: false,
        reasons: [],
        overridePicturePath: nil,
        managedPreferencePaths: []
    )
}

@MainActor
final class SystemWallpaperService {
    private(set) var lastBackup: [WallpaperBackupEntry] = []
    private(set) var lastLockProbe: DesktopLockProbe = .unlocked
    private let backupURL: URL

    init(fileManager: FileManager = .default) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("InkPaper", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        backupURL = dir.appendingPathComponent("system-wallpaper-backup.json")
        loadBackup()
        lastLockProbe = probeDesktopLock()
    }

    func currentWallpaperPath(for screen: NSScreen) -> String? {
        if let url = NSWorkspace.shared.desktopImageURL(for: screen) {
            return url.path
        }
        return nil
    }

    func backupCurrent(displays: [DisplayInfo], registry: DisplayRegistry) {
        var entries: [WallpaperBackupEntry] = []
        for display in displays {
            guard let screen = registry.screen(forDisplayID: display.id) else { continue }
            entries.append(
                WallpaperBackupEntry(
                    displayID: display.id,
                    path: currentWallpaperPath(for: screen)
                )
            )
        }
        lastBackup = entries
        saveBackup()
    }

    func restoreBackup(registry: DisplayRegistry) throws {
        for entry in lastBackup {
            guard let path = entry.path, !path.isEmpty else { continue }
            guard let screen = registry.screen(forDisplayID: entry.displayID) else { continue }
            // 还原不做严格回读，避免阻塞退出路径。
            let url = URL(fileURLWithPath: path)
            var options: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
            options[.imageScaling] = NSNumber(value: NSImageScaling.scaleProportionallyUpOrDown.rawValue)
            options[.allowClipping] = true
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options)
        }
    }

    func apply(
        config: AppConfig,
        displays: [DisplayInfo],
        registry: DisplayRegistry
    ) async throws {
        guard !displays.isEmpty else { throw AppError.noDisplays }

        let probe = probeDesktopLock()
        lastLockProbe = probe
        if probe.isLocked {
            throw AppError.systemWallpaperUnavailable(reason: probe.summary)
        }

        var applied = 0
        for display in displays {
            // 原生-only：跳过，保留系统当前壁纸。
            guard let path = config.imagePath(forDisplayID: display.id) else { continue }
            _ = try ImagePipeline.validate(
                path: path,
                maxBytes: config.maxImageBytes,
                maxDimension: config.maxImageDimension
            )
            guard let screen = registry.screen(forDisplayID: display.id) else { continue }
            try await setDesktopImage(path: path, screen: screen, verify: true)
            applied += 1
        }
        if applied == 0 {
            // 全部「仅原生」：不改系统壁纸，视为成功。
            return
        }
    }

    func setDesktopImage(path: String, screen: NSScreen, verify: Bool) async throws {
        let url = URL(fileURLWithPath: path)
        var options: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
        options[.imageScaling] = NSNumber(value: NSImageScaling.scaleProportionallyUpOrDown.rawValue)
        options[.allowClipping] = true

        do {
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options)
        } catch {
            throw AppError.systemWallpaperSetFailed(reason: error.localizedDescription)
        }

        guard verify else { return }

        // MDM 常会让 API 成功，但随后把壁纸静默打回 override-picture-path。
        let expected = url.resolvingSymlinksInPath().standardizedFileURL.path
        for _ in 0..<8 {
            try await Task.sleep(nanoseconds: 100_000_000)
            let actual = currentWallpaperPath(for: screen).map {
                URL(fileURLWithPath: $0).resolvingSymlinksInPath().standardizedFileURL.path
            }
            if let actual, pathsMatch(actual, expected) {
                return
            }
        }

        let shown = currentWallpaperPath(for: screen) ?? "(无法读取)"
        let probe = probeDesktopLock()
        lastLockProbe = probe
        let extra = probe.isLocked ? "；\(probe.summary)" : ""
        throw AppError.systemWallpaperSetFailed(
            reason: "设置后回读不一致（期望 \(URL(fileURLWithPath: expected).lastPathComponent)，实际 \(URL(fileURLWithPath: shown).lastPathComponent)）\(extra)"
        )
    }

    func isAPIAvailable() -> Bool {
        NSScreen.main != nil
    }

    /// 兼容旧调用：是否被策略锁定。
    func isLikelyLockedByMDM() -> Bool {
        let probe = probeDesktopLock()
        lastLockProbe = probe
        return probe.isLocked
    }

    /// 读取 Managed Preferences / 限制项，判断桌面壁纸是否被强制。
    func probeDesktopLock() -> DesktopLockProbe {
        var reasons: [String] = []
        var overridePath: String?
        var hitFiles: [String] = []

        let candidates = managedDesktopPreferenceURLs()
        for url in candidates {
            guard let dict = readPlist(url) else { continue }
            hitFiles.append(url.path)

            if let locked = boolValue(dict["locked"]), locked {
                reasons.append("托管偏好 locked=true（\(url.lastPathComponent)）")
            }
            if let path = stringValue(dict["override-picture-path"]), !path.isEmpty {
                overridePath = path
                reasons.append("存在 override-picture-path=\(path)")
            }
            // 某些环境把 Background 整段托管进来。
            if dict["Background"] != nil {
                reasons.append("托管偏好包含 Background")
            }
        }

        // Restrictions payload：allowWallpaperModification = false
        for url in managedApplicationAccessURLs() {
            guard let dict = readPlist(url) else { continue }
            if let allow = boolValue(dict["allowWallpaperModification"]), allow == false {
                hitFiles.append(url.path)
                reasons.append("限制项 allowWallpaperModification=false")
            }
        }

        // CFPreferences 强制层（若可读）
        if cfPreferencesIndicateForcedDesktop() {
            reasons.append("CFPreferences 显示桌面偏好被强制")
        }

        let uniqueReasons = Array(NSOrderedSet(array: reasons)) as? [String] ?? reasons
        return DesktopLockProbe(
            isLocked: !uniqueReasons.isEmpty,
            reasons: uniqueReasons,
            overridePicturePath: overridePath,
            managedPreferencePaths: Array(Set(hitFiles)).sorted()
        )
    }

    /// Deep check: set current wallpaper to itself and ensure it sticks.
    func deepWritabilityCheck(screen: NSScreen) async -> Result<Void, AppError> {
        let probe = probeDesktopLock()
        lastLockProbe = probe
        if probe.isLocked {
            return .failure(.systemWallpaperUnavailable(reason: probe.summary))
        }
        guard let current = currentWallpaperPath(for: screen) else {
            return .failure(.systemWallpaperUnavailable(reason: "无法读取当前壁纸路径"))
        }
        do {
            try await setDesktopImage(path: current, screen: screen, verify: true)
            return .success(())
        } catch let error as AppError {
            return .failure(error)
        } catch {
            return .failure(.systemWallpaperSetFailed(reason: error.localizedDescription))
        }
    }

    // MARK: - Managed prefs helpers

    private func managedDesktopPreferenceURLs() -> [URL] {
        let user = NSUserName()
        let roots = [
            "/Library/Managed Preferences/com.apple.desktop.plist",
            "/Library/Managed Preferences/\(user)/com.apple.desktop.plist",
        ]
        return roots.map { URL(fileURLWithPath: $0) }
    }

    private func managedApplicationAccessURLs() -> [URL] {
        let user = NSUserName()
        let roots = [
            "/Library/Managed Preferences/com.apple.applicationaccess.plist",
            "/Library/Managed Preferences/\(user)/com.apple.applicationaccess.plist",
        ]
        return roots.map { URL(fileURLWithPath: $0) }
    }

    private func readPlist(_ url: URL) -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            return dict
        }
        return nil
    }

    private func boolValue(_ any: Any?) -> Bool? {
        switch any {
        case let b as Bool: return b
        case let n as NSNumber: return n.boolValue
        case let s as String:
            let lower = s.lowercased()
            if ["1", "true", "yes"].contains(lower) { return true }
            if ["0", "false", "no"].contains(lower) { return false }
            return nil
        default:
            return nil
        }
    }

    private func stringValue(_ any: Any?) -> String? {
        switch any {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }

    private func cfPreferencesIndicateForcedDesktop() -> Bool {
        // 尝试通过 CFPreferencesCopyAppValue 观察是否能读到托管覆盖路径。
        let key = "override-picture-path" as CFString
        let app = "com.apple.desktop" as CFString
        if let value = CFPreferencesCopyAppValue(key, app) as? String, !value.isEmpty {
            // 仅当 Managed Preferences 文件也存在时，才视为强制，避免误判用户本地值。
            return managedDesktopPreferenceURLs().contains { FileManager.default.fileExists(atPath: $0.path) }
        }
        return false
    }

    private func pathsMatch(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        // 有些系统会把路径标准化或经 /private 前缀。
        let na = (a as NSString).standardizingPath
        let nb = (b as NSString).standardizingPath
        if na == nb { return true }
        return URL(fileURLWithPath: a).lastPathComponent == URL(fileURLWithPath: b).lastPathComponent
            && FileManager.default.contentsEqual(
                atPath: a,
                andPath: b
            )
    }

    private func saveBackup() {
        do {
            let data = try JSONEncoder().encode(lastBackup)
            try data.write(to: backupURL, options: [.atomic])
        } catch {
            NSLog("InkPaper: backup save failed: \(error)")
        }
    }

    private func loadBackup() {
        guard let data = try? Data(contentsOf: backupURL) else { return }
        lastBackup = (try? JSONDecoder().decode([WallpaperBackupEntry].self, from: data)) ?? []
    }
}
