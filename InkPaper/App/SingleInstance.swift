import AppKit
import Foundation

/// 同 Bundle ID 只允许一个进程；第二份启动时激活已有实例并退出自己。
enum SingleInstance {
    static let activateNotification = Notification.Name("com.ink.InkPaper.activateExisting")

    /// - Returns: `true` 表示本进程应继续；`false` 表示已移交已有实例，本进程应立即退出。
    static func acquireOrHandOff() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return true }
        let myPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != myPID && !$0.isTerminated }

        guard let existing = others.first else { return true }

        DistributedNotificationCenter.default().postNotificationName(
            activateNotification,
            object: bundleID,
            userInfo: nil,
            deliverImmediately: true
        )
        _ = existing.activate(options: [.activateIgnoringOtherApps])
        return false
    }

    /// 主实例监听「再次启动」请求，通常用于打开设置窗。
    @discardableResult
    static func startListeningForActivation(handler: @escaping @MainActor () -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(
            forName: activateNotification,
            object: Bundle.main.bundleIdentifier,
            queue: .main
        ) { _ in
            Task { @MainActor in
                handler()
            }
        }
    }
}
