import AppKit

/// 旧版 AppKit 菜单栏实现；当前主路径为 SwiftUI `MenuBarExtra`。
/// 保留空壳以免工程引用断裂，后续可删除。
@MainActor
final class MenuBarController: NSObject {
    func install() {}
    func remove() {}
    func refreshMenu() {}
}
