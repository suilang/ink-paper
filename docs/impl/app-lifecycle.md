# 应用生命周期

## 源码

- `InkPaper/App/InkPaperApp.swift`（`@main` SwiftUI App）
- `InkPaper/App/AppDelegate.swift`
- `InkPaper/App/SingleInstance.swift`
- `InkPaper/App/AppServices.swift`
- `InkPaper/Resources/Info.plist`

## 启动形态

| 项 | 值 |
|----|-----|
| `LSUIElement` | `true`（Info.plist） |
| `activationPolicy` | `.accessory`（始终，不占 Dock） |
| 入口 | 菜单栏 `MenuBarExtra` 标签 **Ink** |

主入口为 SwiftUI：

- `Window("Ink Paper 设置", id: "settings")`
- `MenuBarExtra` 标签为 **Ink** + `photo.on.rectangle`

若 Scene 窗口未及时物化，`AppDelegate.openSettings()` 会创建 AppKit 兜底窗，并短暂升到 `.floating` 再降回 `.normal`。

## 单实例

按 Bundle ID（`com.ink.InkPaper`）约束：

1. `applicationWillFinishLaunching` 调用 `SingleInstance.acquireOrHandOff()`
2. 若已有同 Bundle ID 进程：向其发 `DistributedNotification`（`com.ink.InkPaper.activateExisting`）→ `activate` → 本进程 `exit(0)`（在 bootstrap 之前，避免双 overlay）
3. 主实例收到通知后打开设置窗（与 Dock/访达再次打开行为一致）

Xcode Debug 与已安装包若 Bundle ID 相同，也会互斥。

## 启动顺序

1. SwiftUI App 启动，注入 `AppDelegate`
2. `applicationWillFinishLaunching`：单实例检查（失败则立即退出）
3. `AppServices.shared` 初始化 Config / Display / ModeEngine
4. `applicationDidFinishLaunching`：注册单实例激活监听 → `.accessory` → bootstrap → 按需打开设置
5. 打开设置条件：`openConfigOnLaunch`、尚未选图、或尚未启用壁纸

## 退出

- `applicationWillTerminate` → `modeEngine.shutdown()`
- 关闭设置窗不退出应用

## 排查「点了运行没反应」

1. 菜单栏是否出现 **Ink**（可能在右侧「…」溢出区）
2. 点菜单「打开设置…」
3. Xcode 控制台是否有报错  
（无 Dock 图标属预期行为）

## 已知限制

- 未启用 App Sandbox
- 旧 `MenuBarController` 已空壳化，主路径为 `MenuBarExtra`
