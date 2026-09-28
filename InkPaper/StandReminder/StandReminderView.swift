import SwiftUI

/// 单个提示窗的 SwiftUI 内容：低饱和度主题色背景 + 白色文案 + 倒计时进度条 + 按钮。
///
/// 背景用 `RoundedRectangle.fill` 直接作为 `.background` 的 shape（而非
/// `.background(色) + .clipShape`），避免圆角外残留。通过 `@ObservedObject`
/// 观察引擎，倒计时每次 tick 更新 `presentModel` 时所有窗口的视图自动重绘。
struct StandReminderView: View {
    @ObservedObject var engine: StandReminderEngine
    let size: NSSize
    let onSkip: () -> Void
    let onSnooze: () -> Void

    private var model: StandReminderPresentModel? { engine.presentModel }

    var body: some View {
        if let model {
            content(model: model)
        }
    }

    @ViewBuilder
    private func content(model: StandReminderPresentModel) -> some View {
        VStack(spacing: 22) {
            // 标签：小休 / 大休
            Text(model.isLongBreak ? "大休息时间" : "小休息时间")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.25), in: Capsule())

            // 标题（指导动作主文案）
            Text(model.tip.title)
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            // 具体动作说明
            Text(model.tip.detail)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .lineSpacing(3)

            Spacer(minLength: 16)

            // 倒计时进度条 + 剩余秒数
            VStack(spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.25))
                            .frame(height: 12)
                        Capsule()
                            .fill(Color.white)
                            .frame(width: geo.size.width * model.progress, height: 12)
                            .animation(.linear(duration: 1), value: model.progress)
                    }
                }
                .frame(height: 12)

                HStack {
                    Text(model.countdownText)
                        .font(.title3.monospacedDigit().weight(.medium))
                        .foregroundStyle(.white)
                    Spacer()
                }
            }

            // 按钮：跳过 / 延期
            HStack(spacing: 20) {
                Button("跳过", action: onSkip)
                    .buttonStyle(ReminderButtonStyle(background: .white, foreground: .black))
                Button("延期 5 分", action: onSnooze)
                    .buttonStyle(ReminderButtonStyle(background: Color.white.opacity(0.9), foreground: model.theme.accent))
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 40)
        .padding(.top, 36)
        .padding(.bottom, 32)
        .frame(width: size.width, height: size.height)
        // 用 RoundedRectangle 直接作背景 shape（圆角矩形填充），
        // 不用 .background + .clipShape 组合（后者圆角外可能有残留）。
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(model.theme.bg)
        )
    }
}

/// 自定义按钮样式：实心圆角背景 + 清晰文字，确保彩色背景上高对比可点。
struct ReminderButtonStyle: ButtonStyle {
    let background: Color
    let foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .frame(minWidth: 110)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(background)
                    .opacity(configuration.isPressed ? 0.7 : 1.0)
            )
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }
}

/// 一次提示的完整数据（引擎驱动，所有窗口共享）。
struct StandReminderPresentModel {
    let tip: ActivityTip
    let theme: ReminderTheme
    let isLongBreak: Bool
    let totalSeconds: TimeInterval
    let remainingSeconds: TimeInterval

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return max(0, min(1, remainingSeconds / totalSeconds))
    }

    var countdownText: String {
        let secs = Int(remainingSeconds.rounded(.up))
        if secs >= 60 {
            return String(format: "%d:%02d", secs / 60, secs % 60)
        }
        return "\(secs)s"
    }
}
