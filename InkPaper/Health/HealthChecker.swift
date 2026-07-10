import AppKit
import Foundation

enum CheckSeverity: String, Codable, Equatable {
    case pass
    case warn
    case fail
}

struct CheckItemResult: Identifiable, Equatable {
    let id: String
    let group: String
    let title: String
    let severity: CheckSeverity
    let detail: String
}

struct HealthReport: Equatable {
    var items: [CheckItemResult]
    var checkedAt: Date

    var passCount: Int { items.filter { $0.severity == .pass }.count }
    var warnCount: Int { items.filter { $0.severity == .warn }.count }
    var failCount: Int { items.filter { $0.severity == .fail }.count }

    var summary: HealthCheckSummary {
        HealthCheckSummary(
            passCount: passCount,
            warnCount: warnCount,
            failCount: failCount,
            lines: items.map { "[\($0.severity.rawValue.uppercased())] \($0.id) \($0.title): \($0.detail)" }
        )
    }

    var textReport: String {
        let header = "InkPaper Health Report — \(checkedAt.formatted())"
        return ([header, ""] + summary.lines).joined(separator: "\n")
    }

    var systemModeWritable: Bool {
        !items.contains { $0.id.hasPrefix("A") && $0.severity == .fail }
    }
}

@MainActor
final class HealthChecker {
    func run(
        config: AppConfig,
        displays: [DisplayInfo],
        registry: DisplayRegistry,
        systemWallpaper: SystemWallpaperService,
        overlay: OverlayWallpaperService,
        activeMode: WallpaperMode?,
        deepSystemCheck: Bool = false
    ) async -> HealthReport {
        var items: [CheckItemResult] = []

        // Environment
        let ver = ProcessInfo.processInfo.operatingSystemVersion
        let supported = ver.majorVersion >= 13
        items.append(
            CheckItemResult(
                id: "E01",
                group: "环境",
                title: "系统版本",
                severity: supported ? .pass : .fail,
                detail: "macOS \(ver.majorVersion).\(ver.minorVersion).\(ver.patchVersion)"
            )
        )

        let gui = NSApp != nil && !NSScreen.screens.isEmpty
        items.append(
            CheckItemResult(
                id: "E02",
                group: "环境",
                title: "GUI 登录会话",
                severity: gui ? .pass : .fail,
                detail: gui ? "当前为图形会话" : "非 GUI 会话"
            )
        )

        items.append(
            CheckItemResult(
                id: "E03",
                group: "环境",
                title: "显示器列表",
                severity: displays.isEmpty ? .fail : .pass,
                detail: displays.isEmpty ? "无显示器" : "\(displays.count) 块显示器"
            )
        )

        if let path = config.imagePath {
            let readable = FileManager.default.isReadableFile(atPath: path)
            items.append(
                CheckItemResult(
                    id: "E04",
                    group: "环境",
                    title: "图片读权限",
                    severity: readable ? .pass : .fail,
                    detail: readable ? path : "不可读：\(path)"
                )
            )
        } else {
            items.append(
                CheckItemResult(
                    id: "E04",
                    group: "环境",
                    title: "图片读权限",
                    severity: .warn,
                    detail: "尚未配置全局图片"
                )
            )
        }

        // Mode A
        items.append(
            CheckItemResult(
                id: "A01",
                group: "系统壁纸",
                title: "桌面图 API",
                severity: systemWallpaper.isAPIAvailable() ? .pass : .fail,
                detail: systemWallpaper.isAPIAvailable() ? "可用" : "不可用"
            )
        )

        let mdm = systemWallpaper.probeDesktopLock()
        items.append(
            CheckItemResult(
                id: "A02",
                group: "系统壁纸",
                title: "MDM/策略锁定探测",
                severity: mdm.isLocked ? .fail : .pass,
                detail: mdm.summary
            )
        )

        if deepSystemCheck, let main = NSScreen.main {
            switch await systemWallpaper.deepWritabilityCheck(screen: main) {
            case .success:
                items.append(
                    CheckItemResult(
                        id: "A03",
                        group: "系统壁纸",
                        title: "深度试写",
                        severity: .pass,
                        detail: "试写成功"
                    )
                )
            case .failure(let error):
                items.append(
                    CheckItemResult(
                        id: "A03",
                        group: "系统壁纸",
                        title: "深度试写",
                        severity: .fail,
                        detail: error.localizedDescription
                    )
                )
            }
        } else {
            items.append(
                CheckItemResult(
                    id: "A03",
                    group: "系统壁纸",
                    title: "深度试写",
                    severity: .warn,
                    detail: "未执行（可在诊断页手动运行）"
                )
            )
        }

        if let path = config.imagePath {
            do {
                _ = try ImagePipeline.validate(
                    path: path,
                    maxBytes: config.maxImageBytes,
                    maxDimension: config.maxImageDimension
                )
                items.append(
                    CheckItemResult(
                        id: "A04",
                        group: "系统壁纸",
                        title: "目标图片要求",
                        severity: .pass,
                        detail: "全局图校验通过"
                    )
                )
            } catch {
                items.append(
                    CheckItemResult(
                        id: "A04",
                        group: "系统壁纸",
                        title: "目标图片要求",
                        severity: .fail,
                        detail: error.localizedDescription
                    )
                )
            }
        } else {
            items.append(
                CheckItemResult(
                    id: "A04",
                    group: "系统壁纸",
                    title: "目标图片要求",
                    severity: .warn,
                    detail: "无全局图"
                )
            )
        }

        // Mode B
        items.append(
            CheckItemResult(
                id: "B01",
                group: "底层窗口",
                title: "桌面层窗口能力",
                severity: overlay.canCreateDesktopLevelWindow() ? .pass : .fail,
                detail: "可创建 desktop level 窗口"
            )
        )

        items.append(
            CheckItemResult(
                id: "B02",
                group: "底层窗口",
                title: "层级与 Dock",
                severity: .pass,
                detail: "使用 desktopWindow level，不几何避让 Dock"
            )
        )

        items.append(
            CheckItemResult(
                id: "B03",
                group: "底层窗口",
                title: "点击穿透",
                severity: config.ignoreMouseEvents ? .pass : .fail,
                detail: "ignoresMouseEvents=\(config.ignoreMouseEvents)"
            )
        )

        if overlay.isActive {
            let match = overlay.activeWindowCount == displays.count
            items.append(
                CheckItemResult(
                    id: "B04",
                    group: "底层窗口",
                    title: "窗口数与屏幕数",
                    severity: match ? .pass : .fail,
                    detail: "窗口 \(overlay.activeWindowCount) / 屏幕 \(displays.count)"
                )
            )
        } else {
            items.append(
                CheckItemResult(
                    id: "B04",
                    group: "底层窗口",
                    title: "窗口数与屏幕数",
                    severity: .warn,
                    detail: "底层模式未激活"
                )
            )
        }

        items.append(
            CheckItemResult(
                id: "B05",
                group: "底层窗口",
                title: "全 Space 可见",
                severity: .pass,
                detail: config.applyToAllSpaces ? "已配置 canJoinAllSpaces" : "仅当前 Space"
            )
        )

        // Resources
        func appendResourceChecks(prefix: String, path: String?) {
            guard let path else {
                items.append(
                    CheckItemResult(
                        id: "\(prefix)01",
                        group: "资源",
                        title: "路径存在",
                        severity: .warn,
                        detail: "未配置"
                    )
                )
                return
            }
            let exists = FileManager.default.fileExists(atPath: path)
            items.append(
                CheckItemResult(
                    id: "R01",
                    group: "资源",
                    title: "路径存在",
                    severity: exists ? .pass : .fail,
                    detail: path
                )
            )
            let readable = FileManager.default.isReadableFile(atPath: path)
            items.append(
                CheckItemResult(
                    id: "R02",
                    group: "资源",
                    title: "文件可读",
                    severity: readable ? .pass : .fail,
                    detail: readable ? "可读" : "不可读"
                )
            )
            do {
                _ = try ImagePipeline.validate(
                    path: path,
                    maxBytes: config.maxImageBytes,
                    maxDimension: config.maxImageDimension
                )
                items.append(
                    CheckItemResult(
                        id: "R03",
                        group: "资源",
                        title: "可解码",
                        severity: .pass,
                        detail: "OK"
                    )
                )
                items.append(
                    CheckItemResult(
                        id: "R04",
                        group: "资源",
                        title: "大小/尺寸限制",
                        severity: .pass,
                        detail: "未超限"
                    )
                )
            } catch let error as AppError {
                let id: String
                let title: String
                switch error {
                case .imageUndecodable:
                    id = "R03"; title = "可解码"
                case .imageTooLarge, .imageDimensionTooLarge:
                    id = "R04"; title = "大小/尺寸限制"
                default:
                    id = "R03"; title = "可解码"
                }
                items.append(
                    CheckItemResult(
                        id: id,
                        group: "资源",
                        title: title,
                        severity: .fail,
                        detail: error.localizedDescription
                    )
                )
            } catch {
                items.append(
                    CheckItemResult(
                        id: "R03",
                        group: "资源",
                        title: "可解码",
                        severity: .fail,
                        detail: error.localizedDescription
                    )
                )
            }
        }

        appendResourceChecks(prefix: "R", path: config.imagePath)

        if config.perDisplayEnabled {
            var covered = 0
            var nativeOnly: [String] = []
            var missing: [String] = []
            for display in displays {
                if config.usesNativeWallpaperOnly(forDisplayID: display.id) {
                    nativeOnly.append(display.localizedName)
                } else if config.imagePath(forDisplayID: display.id) != nil {
                    covered += 1
                } else {
                    missing.append(display.localizedName)
                }
            }
            let detailParts: [String] = [
                covered > 0 ? "覆盖 \(covered) 屏" : nil,
                nativeOnly.isEmpty ? nil : "原生 \(nativeOnly.joined(separator: ", "))",
                missing.isEmpty ? nil : "缺图 \(missing.joined(separator: ", "))"
            ].compactMap { $0 }
            let severity: CheckSeverity
            if covered == 0 {
                severity = .fail
            } else if missing.isEmpty {
                severity = .pass
            } else {
                severity = .fail
            }
            items.append(
                CheckItemResult(
                    id: "R05",
                    group: "资源",
                    title: "分屏图片完整性",
                    severity: severity,
                    detail: detailParts.isEmpty ? "无可用分屏配置" : detailParts.joined(separator: "；")
                )
            )
        } else {
            items.append(
                CheckItemResult(
                    id: "R05",
                    group: "资源",
                    title: "分屏图片完整性",
                    severity: .pass,
                    detail: "未启用分屏"
                )
            )
        }

        // State
        let preferred = config.preferredMode
        let consistency: CheckSeverity
        let consistencyDetail: String
        switch (preferred, activeMode) {
        case (.auto, _):
            consistency = .pass
            consistencyDetail = "自动模式，实际=\(activeMode?.displayName ?? "未启用")"
        case (.system, .system), (.overlay, .overlay):
            consistency = .pass
            consistencyDetail = "偏好与实际一致"
        case (.system, .overlay):
            consistency = .warn
            consistencyDetail = "偏好系统壁纸，实际为底层窗口（可能已降级）"
        case (.overlay, .system):
            consistency = .warn
            consistencyDetail = "偏好底层窗口，实际为系统壁纸"
        case (_, nil):
            consistency = .warn
            consistencyDetail = "尚未启用任何模式"
        }
        items.append(
            CheckItemResult(
                id: "S01",
                group: "状态",
                title: "偏好与实际模式",
                severity: consistency,
                detail: consistencyDetail
            )
        )

        let dual = overlay.isActive && activeMode == .system
        items.append(
            CheckItemResult(
                id: "S02",
                group: "状态",
                title: "模式互斥",
                severity: dual ? .fail : .pass,
                detail: dual ? "检测到底层窗口与系统模式并存风险" : "互斥正常"
            )
        )

        if overlay.isActive {
            let sync = overlay.activeWindowCount == displays.count
            items.append(
                CheckItemResult(
                    id: "S03",
                    group: "状态",
                    title: "窗口与屏幕同步",
                    severity: sync ? .pass : .fail,
                    detail: sync ? "已同步" : "不同步"
                )
            )
        } else {
            items.append(
                CheckItemResult(
                    id: "S03",
                    group: "状态",
                    title: "窗口与屏幕同步",
                    severity: .pass,
                    detail: "底层未启用"
                )
            )
        }

        let backupOK = !systemWallpaper.lastBackup.isEmpty
        items.append(
            CheckItemResult(
                id: "S04",
                group: "状态",
                title: "系统壁纸备份",
                severity: config.backupSystemWallpaperBeforeSwitch
                    ? (backupOK ? .pass : .warn)
                    : .pass,
                detail: backupOK
                    ? "已有 \(systemWallpaper.lastBackup.count) 条备份"
                    : (config.backupSystemWallpaperBeforeSwitch ? "尚无备份" : "备份未启用")
            )
        )

        return HealthReport(items: items, checkedAt: Date())
    }
}
