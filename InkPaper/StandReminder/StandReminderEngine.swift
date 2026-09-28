import AppKit
import Combine
import Foundation

/// 活动提醒调度引擎。
///
/// 状态机：
///   idle ──(interval 到点)──▶ showing ──(倒计时结束/跳过)──▶ idle（重排下次）
///                                └──(延期)──▶ snoozed ──(snooze 到)──▶ showing
///
/// 与壁纸模式解耦：不触碰 overlay/system 壁纸窗口，独立维护提示窗。
@MainActor
final class StandReminderEngine: ObservableObject {
    enum State: Equatable {
        case idle
        case showing
        case snoozing
        case paused
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var presentModel: StandReminderPresentModel?
    @Published private(set) var nextFireDate: Date?
    @Published private(set) var isWindowVisible = false

    private weak var configStore: ConfigStore?
    private weak var displayRegistry: DisplayRegistry?
    private var windows: [String: StandReminderWindow] = [:]

    private var scheduleTimer: Timer?
    private var countdownTimer: Timer?
    private var totalSeconds: TimeInterval = 0
    private var fireDate: Date?
    private var wakeObserver: NSObjectProtocol?
    private var displayCancellable: AnyCancellable?

    init() {}

    func bind(to configStore: ConfigStore, displayRegistry: DisplayRegistry) {
        self.configStore = configStore
        self.displayRegistry = displayRegistry
        // 监听屏变：观察 @Published displays，提示窗显示时同步增删窗口。
        // 不占用 ModeEngine 已有的 onDisplaysChanged 单回调。
        displayCancellable = displayRegistry.$displays
            .removeDuplicates(by: { lhs, rhs in
                Set(lhs.map(\.id)) == Set(rhs.map(\.id))
            })
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handleDisplaysChanged()
                }
            }
    }

    // MARK: - Lifecycle

    func bootstrap() {
        guard let configStore else { return }
        guard configStore.config.standReminderEnabled else {
            state = .idle
            return
        }
        startSchedule()
        registerWakeNotification()
    }

    func shutdown() {
        scheduleTimer?.invalidate()
        scheduleTimer = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
        dismissWindows()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        displayCancellable?.cancel()
        displayCancellable = nil
        state = .idle
    }

    /// 配置变更后重新对齐调度（开关切换、间隔变更等）。
    func reload() {
        guard let configStore else { return }
        scheduleTimer?.invalidate()
        scheduleTimer = nil
        if configStore.config.standReminderEnabled {
            if state == .paused {
                // 暂停态下仅记录，不启动
                return
            }
            startSchedule()
        } else {
            dismissWindows()
            state = .idle
            nextFireDate = nil
            fireDate = nil
        }
    }

    // MARK: - Scheduling

    private func startSchedule(intervalMinutes: Int? = nil) {
        guard let configStore else { return }
        scheduleTimer?.invalidate()
        let minutes = intervalMinutes ?? configStore.config.standReminderInterval.rawValue
        let interval = TimeInterval(minutes) * 60
        fireDate = Date(timeIntervalSinceNow: interval)
        nextFireDate = fireDate
        // 用 .common modes，避免交互时调度 Timer 不触发。
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.present()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        scheduleTimer = timer
    }

    private func present() {
        guard let configStore else { return }
        // 计算本次休息时长（自动交替：每 4 次中第 4 次为大休）。
        let cycleIndex = configStore.config.standReminderCycleIndex
        let config = configStore.config
        let isLong: Bool
        let duration: TimeInterval
        if config.standReminderAutoAlternate {
            // 每 4 次循环，第 4 次（index % 4 == 3）为大休；若关闭大休息则恒为小休。
            let wouldBeLong = cycleIndex % 4 == 3
            isLong = wouldBeLong && config.standReminderLongBreakEnabled
            duration = isLong ? ReminderBreakDuration.long.seconds : ReminderBreakDuration.short.seconds
        } else {
            let preferred = config.standReminderPreferredBreak
            // 固定模式下若关闭大休息，强制使用小休时长。
            isLong = preferred == .long && config.standReminderLongBreakEnabled
            duration = isLong ? ReminderBreakDuration.long.seconds : ReminderBreakDuration.short.seconds
        }
        let theme = ReminderTheme.pick(cycleIndex: cycleIndex)
        let tip = ActivityTips.pick(cycleIndex: cycleIndex)
        totalSeconds = duration

        presentModel = StandReminderPresentModel(
            tip: tip,
            theme: theme,
            isLongBreak: isLong,
            totalSeconds: duration,
            remainingSeconds: duration
        )
        state = .showing
        showWindows()

        // 倒计时：必须加到 .common modes，否则用户与窗口交互（鼠标移动/按钮悬停）
        // 时 runloop 进入 .eventTracking mode，Timer 不触发，倒计时会卡住不动。
        countdownTimer?.invalidate()
        let startDate = Date()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                let elapsed = Date().timeIntervalSince(startDate)
                let remaining = max(0, self.totalSeconds - elapsed)
                guard let pm = self.presentModel else { return }
                self.presentModel = StandReminderPresentModel(
                    tip: pm.tip,
                    theme: pm.theme,
                    isLongBreak: pm.isLongBreak,
                    totalSeconds: self.totalSeconds,
                    remainingSeconds: remaining
                )
                if remaining <= 0 {
                    self.complete()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer

        // 记录触发时间 + 推进 cycleIndex（跳过算 1 次；延期在 snooze 里不增）。
        configStore.update {
            $0.standReminderLastFiredAt = Date()
            $0.standReminderCycleIndex += 1
        }
    }

    private func complete() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        dismissWindows()
        presentModel = nil
        state = .idle
        startSchedule()
    }

    // MARK: - User actions

    func skip() {
        guard state == .showing else { return }
        countdownTimer?.invalidate()
        countdownTimer = nil
        dismissWindows()
        presentModel = nil
        state = .idle
        // cycleIndex 已在 present() 推进；这里不再增。
        startSchedule()
    }

    func snooze() {
        guard let configStore, state == .showing else { return }
        countdownTimer?.invalidate()
        countdownTimer = nil
        dismissWindows()
        presentModel = nil
        state = .snoozing
        let snoozeMinutes = configStore.config.standReminderSnoozeMinutes
        // 延期不增 cycleIndex，避免延期占掉一个长休名额。
        startSchedule(intervalMinutes: snoozeMinutes)
        // 延期后的下一次其实是 present，状态会在 present 时切回 showing。
    }

    /// 立即触发一次休息（菜单栏「立即休息」）。
    func triggerNow() {
        guard state != .showing else { return }
        scheduleTimer?.invalidate()
        scheduleTimer = nil
        present()
    }

    /// 暂停/恢复（菜单栏「暂停/恢复提醒」）。
    func togglePause() {
        switch state {
        case .paused:
            state = .idle
            startSchedule()
        default:
            scheduleTimer?.invalidate()
            scheduleTimer = nil
            countdownTimer?.invalidate()
            countdownTimer = nil
            dismissWindows()
            presentModel = nil
            state = .paused
            nextFireDate = nil
            fireDate = nil
        }
    }

    // MARK: - Windows

    private func showWindows() {
        guard let configStore, let displayRegistry else { return }
        let mode = configStore.config.standReminderDisplayMode.normalized
        let displays = displayRegistry.displays
        let mainDisplay = displays.first(where: { $0.isMain }) ?? displays.first
        let externalDisplay = displays.first(where: { !$0.isMain })

        var targetDisplays: [DisplayInfo] = []
        switch mode {
        case .mainOnly:
            if let mainDisplay { targetDisplays.append(mainDisplay) }
        case .externalOnly:
            // 无外接屏时退化为主屏，不报错。
            if let externalDisplay { targetDisplays.append(externalDisplay) }
            else if let mainDisplay { targetDisplays.append(mainDisplay) }
        case .all:
            if let mainDisplay { targetDisplays.append(mainDisplay) }
            if let externalDisplay { targetDisplays.append(externalDisplay) }
        case .single, .dual:
            // 已 normalized，不会走到；保留以防遗漏。
            if let mainDisplay { targetDisplays.append(mainDisplay) }
        }

        // 销毁不在目标列表中的窗口
        let targetIDs = Set(targetDisplays.map(\.id))
        for id in windows.keys where !targetIDs.contains(id) {
            destroyWindow(id: id)
        }

        guard let model = presentModel else { return }
        for display in targetDisplays {
            guard let screen = displayRegistry.screen(forDisplayID: display.id) else { continue }
            // 宽度取该屏宽度的一半，最小 800；高度按宽高比固定（内容刚好填满）。
            let screenWidth = screen.frame.width
            let width = max(800, min(screenWidth * 0.5, 1000))
            let height: CGFloat = model.isLongBreak ? 480 : 440
            let contentSize = NSSize(width: width, height: height)
            let window: StandReminderWindow
            if let existing = windows[display.id] {
                window = existing
            } else {
                window = StandReminderWindow(screen: screen, displayID: display.id, contentSize: contentSize)
                windows[display.id] = window
            }
            // 先 setRootView（会重置窗口尺寸/位置），再 relayout 强制重新居中并锁尺寸。
            window.setRootView(StandReminderView(
                engine: self,
                size: contentSize,
                onSkip: { [weak self] in self?.skip() },
                onSnooze: { [weak self] in self?.snooze() }
            ))
            window.relayout(on: screen, contentSize: contentSize)
            window.orderFrontRegardless()
        }
        isWindowVisible = true
    }

    private func dismissWindows() {
        for id in Array(windows.keys) {
            destroyWindow(id: id)
        }
        isWindowVisible = false
    }

    private func destroyWindow(id: String) {
        windows[id]?.orderOut(nil)
        windows[id]?.close()
        windows.removeValue(forKey: id)
    }

    private func handleDisplaysChanged() {
        guard state == .showing, isWindowVisible else { return }
        // 提示窗正显示时按新屏集合重建窗口。
        showWindows()
    }

    // MARK: - Sleep / Wake

    private func registerWakeNotification() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // 睡眠唤醒后重新对齐调度，避免错过期间的提醒。
                self?.reload()
            }
        }
    }
}
