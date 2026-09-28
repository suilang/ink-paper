import SwiftUI

struct GeneralPage: View {
    @ObservedObject var state: SettingsSharedState

    private var configStore: ConfigStore? { state.configStore }
    private var modeEngine: ModeEngine? { state.modeEngine }

    var body: some View {
        Form {
            Toggle("登录时启动", isOn: Binding(
                get: { configStore?.config.launchAtLogin ?? false },
                set: { value in
                    configStore?.update { $0.launchAtLogin = value }
                    configStore?.applyLaunchAtLogin()
                    state.statusBanner = value ? "已开启登录启动" : "已关闭登录启动"
                }
            ))
            Toggle("显示菜单栏图标", isOn: state.binding(\.showMenuBarExtra))
            Toggle("启动时打开设置", isOn: state.binding(\.openConfigOnLaunch))
            Toggle("启动时健康检查", isOn: state.binding(\.checkOnLaunch))
            Toggle("显示器变化后重建底层窗口", isOn: state.binding(\.restoreOnDisplayChange))
        }
        .formStyle(.grouped)
        .padding(8)
        .disabled(modeEngine?.isBusy ?? false)
    }
}
