import SwiftUI

/// 提示窗主题色轮转。每次触发按 `cycleIndex` 取一组低饱和度配色，
/// 作用于背景（低饱和度）与按钮强调（主题色）。
struct ReminderTheme: Sendable {
    /// 主题强调色（按钮、进度条填充、标签）。
    let accent: Color
    /// 低饱和度背景色（面板背景）。
    let bg: Color
    let name: String

    static let all: [ReminderTheme] = [
        .init(accent: Color(red: 0.30, green: 0.65, blue: 0.55),
              bg: Color(red: 0.42, green: 0.56, blue: 0.52),
              name: "薄荷青"),
        .init(accent: Color(red: 0.85, green: 0.55, blue: 0.35),
              bg: Color(red: 0.58, green: 0.50, blue: 0.46),
              name: "暖橙"),
        .init(accent: Color(red: 0.55, green: 0.45, blue: 0.80),
              bg: Color(red: 0.50, green: 0.48, blue: 0.60),
              name: "薰衣紫"),
        .init(accent: Color(red: 0.35, green: 0.55, blue: 0.82),
              bg: Color(red: 0.46, green: 0.52, blue: 0.62),
              name: "天空蓝"),
        .init(accent: Color(red: 0.82, green: 0.50, blue: 0.62),
              bg: Color(red: 0.58, green: 0.50, blue: 0.54),
              name: "樱粉"),
        .init(accent: Color(red: 0.45, green: 0.70, blue: 0.40),
              bg: Color(red: 0.50, green: 0.58, blue: 0.48),
              name: "嫩芽绿"),
    ]

    /// 按 `cycleIndex` 轮转取一组主题色。
    static func pick(cycleIndex: Int) -> ReminderTheme {
        let count = all.count
        let idx = ((cycleIndex % count) + count) % count
        return all[idx]
    }
}
