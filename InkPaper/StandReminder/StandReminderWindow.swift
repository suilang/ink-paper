import AppKit
import SwiftUI

/// 活动提醒提示窗：非全屏、居中、floating 层级、可点按钮但不抢焦点。
///
/// 用 `NSWindow` + `.borderless`（单用，不加 `.nonactivatingPanel`），
/// 完全无系统装饰与默认背景；窗口 `backgroundColor = .clear` + `hasShadow = false`，
/// 可见区域全部由 SwiftUI 内容（`RoundedRectangle.fill` 背景）绘制。
final class StandReminderWindow: NSWindow {
    let displayID: String

    init(screen: NSScreen, displayID: String, contentSize: NSSize) {
        self.displayID = displayID
        super.init(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        configure()
        setFrameOrigin(screen.frame.origin)
        center(to: screen)
    }

    /// 相对指定屏居中（用该屏 visibleFrame 的中心）。
    private func center(to screen: NSScreen) {
        let v = screen.visibleFrame
        setFrameOrigin(NSPoint(
            x: v.midX - frame.width / 2,
            y: v.midY - frame.height / 2
        ))
    }

    private func configure() {
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        animationBehavior = .none
        applySizeConstraints()
    }

    /// 锁死内容尺寸，防止 NSHostingController 自适应把窗口缩到内容自然尺寸。
    private func applySizeConstraints() {
        contentMinSize = frame.size
        contentMaxSize = frame.size
        contentResizeIncrements = NSSize(width: 1, height: 1)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// 复用窗口时：重新居中、更新尺寸与约束。
    func relayout(on screen: NSScreen, contentSize: NSSize) {
        setFrame(NSRect(origin: frame.origin, size: contentSize), display: true)
        let v = screen.visibleFrame
        setFrameOrigin(NSPoint(
            x: v.midX - contentSize.width / 2,
            y: v.midY - contentSize.height / 2
        ))
        applySizeConstraints()
    }

    /// 用 SwiftUI 内容托管。
    func setRootView<V: View>(_ rootView: V) {
        let hosting = NSHostingController(rootView: rootView)
        if #available(macOS 15.0, *) {
            hosting.sizingOptions = []
        }
        contentViewController = hosting
    }
}
