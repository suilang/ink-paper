import Foundation

enum AppError: LocalizedError, Equatable {
    case imageMissing(path: String)
    case imageUnreadable(path: String)
    case imageUndecodable(path: String)
    case imageTooLarge(path: String, bytes: Int64)
    case imageDimensionTooLarge(path: String, width: Int, height: Int)
    case noDisplays
    case systemWallpaperUnavailable(reason: String)
    case systemWallpaperSetFailed(reason: String)
    case overlayWindowFailed(reason: String)
    case modeSwitchFailed(reason: String)
    case noImageConfigured
    case configCorrupted

    var errorDescription: String? {
        switch self {
        case .imageMissing(let path):
            return "图片不存在：\(path)"
        case .imageUnreadable(let path):
            return "图片不可读：\(path)"
        case .imageUndecodable(let path):
            return "无法解码图片：\(path)"
        case .imageTooLarge(let path, let bytes):
            return "图片过大（\(bytes) 字节）：\(path)"
        case .imageDimensionTooLarge(let path, let width, let height):
            return "图片尺寸过大（\(width)×\(height)）：\(path)"
        case .noDisplays:
            return "未检测到可用显示器"
        case .systemWallpaperUnavailable(let reason):
            return "系统壁纸不可用：\(reason)"
        case .systemWallpaperSetFailed(let reason):
            return "设置系统壁纸失败：\(reason)"
        case .overlayWindowFailed(let reason):
            return "底层窗口失败：\(reason)"
        case .modeSwitchFailed(let reason):
            return "模式切换失败：\(reason)"
        case .noImageConfigured:
            return "尚未选择壁纸图片"
        case .configCorrupted:
            return "配置损坏，已回退默认值"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .imageMissing, .imageUnreadable, .imageUndecodable, .imageTooLarge, .imageDimensionTooLarge, .noImageConfigured:
            return "请在设置中重新选择有效的本地图片。"
        case .systemWallpaperUnavailable, .systemWallpaperSetFailed:
            return "可切换到底层窗口模式，或检查是否被 MDM/配置描述文件锁定。"
        case .overlayWindowFailed:
            return "请运行诊断，或重启应用后重试。"
        case .modeSwitchFailed:
            return "请查看诊断页中的检查结果。"
        case .noDisplays:
            return "请确认至少有一块显示器处于活动状态。"
        case .configCorrupted:
            return "请重新配置壁纸与模式偏好。"
        }
    }
}
