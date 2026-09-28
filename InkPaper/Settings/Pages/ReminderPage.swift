import SwiftUI

/// 活动提醒设置页：启用 → 间隔 → 展示方式 → 休息时长 → 操作。
struct ReminderPage: View {
    @ObservedObject var configStore: ConfigStore
    @ObservedObject var standReminder: StandReminderEngine

    var body: some View {
        Form {
            Section {
                enableControls
            } header: {
                Text("启用")
            } footer: {
                Text("开启后每隔一段时间弹出居中、半透明的提示窗，提醒你活动一下。提示窗不覆盖全屏，可跳过或延期 5 分钟。")
                    .font(.caption)
            }

            if configStore.config.standReminderEnabled {
                Section("提醒间隔") {
                    Picker(
                        "每隔",
                        selection: Binding(
                            get: { configStore.config.standReminderInterval },
                            set: { value in
                                configStore.update { $0.standReminderInterval = value }
                                standReminder.reload()
                            }
                        )
                    ) {
                        ForEach(ReminderInterval.allCases) { interval in
                            Text(interval.displayName).tag(interval)
                        }
                    }
                }

                Section("展示方式") {
                    Picker(
                        "提示窗范围",
                        selection: Binding(
                            get: { configStore.config.standReminderDisplayMode.normalized },
                            set: { value in
                                configStore.update { $0.standReminderDisplayMode = value }
                            }
                        )
                    ) {
                        ForEach([ReminderDisplayMode.mainOnly, .externalOnly, .all]) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    Text("选「仅副屏」时若无外接屏会自动改在主屏显示。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section("休息时长") {
                    Toggle(
                        "自动交替大小休息",
                        isOn: Binding(
                            get: { configStore.config.standReminderAutoAlternate },
                            set: { value in
                                configStore.update { $0.standReminderAutoAlternate = value }
                            }
                        )
                    )
                    Toggle(
                        "启用大休息",
                        isOn: Binding(
                            get: { configStore.config.standReminderLongBreakEnabled },
                            set: { value in
                                configStore.update { $0.standReminderLongBreakEnabled = value }
                            }
                        )
                    )
                    if !configStore.config.standReminderAutoAlternate {
                        Picker(
                            "固定休息时长",
                            selection: Binding(
                                get: { configStore.config.standReminderPreferredBreak },
                                set: { value in
                                    configStore.update { $0.standReminderPreferredBreak = value }
                                }
                            )
                        ) {
                            ForEach(ReminderBreakDuration.allCases) { duration in
                                Text(duration.displayName).tag(duration)
                            }
                        }
                    } else {
                        LabeledContent("小休息", value: "\(ReminderBreakDuration.short.displayName)")
                        if configStore.config.standReminderLongBreakEnabled {
                            LabeledContent("大休息", value: "\(ReminderBreakDuration.long.displayName)")
                            Text("每 3 次小休后自动来 1 次大休，更贴近健康节奏。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("已关闭大休息，所有提醒均为小休息时长。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("延期") {
                    LabeledContent("延期时长") {
                        Text("5 分钟（固定）")
                            .foregroundStyle(.secondary)
                    }
                    Text("点击提示窗「延期 5 分」会延后 5 分钟再弹，不会占用长休名额。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section("操作") {
                    Button("立即休息") {
                        standReminder.triggerNow()
                    }
                    if standReminder.state == .paused {
                        Button("恢复提醒") {
                            standReminder.togglePause()
                        }
                    } else {
                        Button("暂停提醒") {
                            standReminder.togglePause()
                        }
                    }
                    if let next = standReminder.nextFireDate {
                        LabeledContent("下次提醒") {
                            Text(next.formatted(.dateTime.hour().minute().second()))
                                .foregroundStyle(.secondary)
                        }
                    } else if standReminder.state == .paused {
                        LabeledContent("状态") {
                            Text("已暂停")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }

    private var enableControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(
                "启用活动提醒",
                isOn: Binding(
                    get: { configStore.config.standReminderEnabled },
                    set: { enabled in
                        configStore.update { $0.standReminderEnabled = enabled }
                        standReminder.reload()
                    }
                )
            )

            HStack(spacing: 8) {
                statusBadge
                if standReminder.state == .showing {
                    ProgressView().controlSize(.small)
                }
            }
        }
    }

    private var statusBadge: some View {
        let text: String
        let color: Color
        switch standReminder.state {
        case .showing:
            text = "休息中"
            color = .green
        case .snoozing:
            text = "已延期"
            color = .orange
        case .paused:
            text = "已暂停"
            color = .secondary
        case .idle:
            if configStore.config.standReminderEnabled {
                text = "运行中"
                color = .green
            } else {
                text = "未启用"
                color = .secondary
            }
        }
        return Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
