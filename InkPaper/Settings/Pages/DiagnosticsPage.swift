import AppKit
import SwiftUI

struct DiagnosticsPage: View {
    @ObservedObject var state: SettingsSharedState

    private var modeEngine: ModeEngine? { state.modeEngine }
    private var configStore: ConfigStore? { state.configStore }

    var body: some View {
        Form {
            Section {
                HStack {
                    Button("运行检查") {
                        guard let modeEngine else { return }
                        Task {
                            let report = await modeEngine.runHealthCheck(deep: false)
                            state.healthItems = report.items
                            state.healthCheckedAt = report.checkedAt
                            state.statusBanner = "检查完成：通过 \(report.passCount) / 警告 \(report.warnCount) / 失败 \(report.failCount)"
                        }
                    }
                    .disabled(modeEngine?.isBusy ?? false)

                    Button("深度检查（可能闪屏）") {
                        guard let modeEngine else { return }
                        Task {
                            let report = await modeEngine.runHealthCheck(deep: true)
                            state.healthItems = report.items
                            state.healthCheckedAt = report.checkedAt
                            state.statusBanner = "深度检查完成"
                        }
                    }
                    .disabled(modeEngine?.isBusy ?? false)

                    Button("复制报告") {
                        guard let modeEngine else { return }
                        Task {
                            let text: String
                            if state.healthItems.isEmpty {
                                text = await modeEngine.runHealthCheck(deep: false).textReport
                            } else {
                                text = HealthReport(items: state.healthItems, checkedAt: state.healthCheckedAt ?? Date()).textReport
                            }
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                            state.alertMessage = "报告已复制到剪贴板"
                        }
                    }
                }
                if let at = state.healthCheckedAt ?? configStore?.config.lastCheckAt {
                    Text("上次检查：\(at.formatted())").font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("结果") {
                if state.healthItems.isEmpty {
                    if (configStore?.config.lastCheckReport.lines.isEmpty ?? true) {
                        Text("尚未运行检查")
                    } else {
                        ForEach(configStore?.config.lastCheckReport.lines ?? [], id: \.self) { line in
                            Text(line).font(.caption)
                        }
                    }
                } else {
                    ForEach(state.healthItems) { item in
                        HStack(alignment: .top) {
                            Circle()
                                .fill(item.severity == .pass ? Color.green : item.severity == .warn ? Color.orange : Color.red)
                                .frame(width: 8, height: 8)
                                .padding(.top, 6)
                            VStack(alignment: .leading) {
                                Text("\(item.id) · \(item.title)")
                                Text(item.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }
}
