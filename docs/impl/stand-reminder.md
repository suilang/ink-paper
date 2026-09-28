# 活动提醒（Stand Reminder）

## 源码

- `InkPaper/StandReminder/StandReminderEngine.swift`（调度引擎 + 状态机 + 双屏窗口托管）
- `InkPaper/StandReminder/StandReminderWindow.swift`（NSPanel 子类：磨砂/半透明/居中/floating）
- `InkPaper/StandReminder/StandReminderView.swift`（SwiftUI 内容：文案 + 进度条 + 按钮）
- `InkPaper/StandReminder/ActivityTips.swift`（指导动作文案库）
- `InkPaper/StandReminder/ReminderTheme.swift`（主题色轮转）
- 配置：`AppConfig` 的 `standReminder*` 字段，见 [config-store.md](./config-store.md)

## 定位

独立于壁纸模式（不触碰 overlay/system 壁纸窗口）。每隔一段时间弹居中、半透明、磨砂的提示窗，提醒用户活动一下手脚/肩颈/眼部。

## 状态机

```
idle ──(interval 到点)──▶ showing ──(倒计时结束/跳过)──▶ idle（重排下次）
                               └──(延期)──▶ snoozing ──(5 分钟到)──▶ showing
                                                    └──(togglePause)──▶ paused ──(togglePause)──▶ idle
```

## 配置

| 字段 | 默认 | 行为 |
|------|------|------|
| `standReminderEnabled` | `false` | 总开关 |
| `standReminderInterval` | `min20` | 10/15/20/25 分钟（每 5 分钟一档） |
| `standReminderDisplayMode` | `single` | 仅主屏 / 主屏+主外接屏 |
| `standReminderAutoAlternate` | `true` | 每 3 次小休后 1 次大休 |
| `standReminderPreferredBreak` | `short` | 自动交替关闭时的固定时长（20s/60s） |
| `standReminderSnoozeMinutes` | `5` | 延期时长（固定） |
| `standReminderCycleIndex` | `0` | 自动交替计数 + 主题色/文案轮转 |

## 大小休息决策

自动交替开启时（默认）：

```
cycleIndex: 0 1 2 | 3   4 5 6 | 7   8 ...
duration :  S S S | L   S S S | L   S ...
判断: cycleIndex % 4 == 3 → long，其余 → short
```

- 每次到点 `present()` 前按上式决定本次时长。
- **跳过**算 1 次（`cycleIndex+1`），推进长休名额。
- **延期**不算（不增计数），避免延期占掉一个长休名额。

## 提示窗属性

| 属性 | 值 | 说明 |
|------|-----|------|
| 类 | `NSPanel` | `.nonactivatingPanel` 不抢焦点 |
| `styleMask` | `.borderless` + `.nonactivatingPanel` | 无标题栏 |
| `level` | `.floating` | 盖在普通窗口上，不强占全屏 |
| `isOpaque` | `false` | 透明背景，让磨砂透出 |
| `backgroundColor` | `.clear` | |
| `canBecomeKey` | `true` | 仅为按钮可点 |
| `canBecomeMain` | `false` | |
| `collectionBehavior` | `.canJoinAllSpaces` + `.stationary` + `.ignoresCycle` | 跨 Space 可见 |
| 尺寸 | 小休 360×220 / 大休 420×260 | 不覆盖全屏 |
| 居中 | 该屏 `screen.frame.midX/midY` | |
| 磨砂 | `.regularMaterial` + `RoundedRectangle(cornerRadius: 20)` | 双层保障 |

## 颜色自动切换

`ReminderTheme.all` 6 组柔和配色（薄荷青/暖橙/薰衣紫/天空蓝/樱粉/嫩芽绿），每次 `present()` 按 `cycleIndex % 6` 轮转，作用于进度条、按钮强调、顶部色条、背景渐变。

## 单屏 / 双屏

- `single`：仅主屏开窗。
- `dual`：主屏 + 第一块非主屏外接屏各开一窗；无外接屏时静默退化为单窗，不报错。
- 两窗共享同一份倒计时状态、同一主题色、同一文案（`StandReminderEngine` 单一驱动，窗口只负责渲染）。
- 屏变监听：观察 `DisplayRegistry.$displays`（不占用 `onDisplaysChanged` 单回调，避免与 ModeEngine 冲突）；提示窗正显示时按新屏集合增删窗口。

## 倒计时

- `Timer.scheduledTimer` 每秒刷新 `presentModel.remainingSeconds`。
- 进度条宽度按 `remaining/total` 线性收缩，`.animation(.linear(duration: 1))`。
- 到 0 自动 `complete()` → 关窗 → 排下次。

## 用户动作

| 动作 | 行为 | 计数 |
|------|------|------|
| 跳过 | 立即关窗，按 `interval` 排下次 | `cycleIndex+1` |
| 延期 5 分 | 立即关窗，按 5 分钟排下次 | 不增 |
| 倒计时结束 | 自动关窗 + 排下次 | 已在 `present()` 推进 |
| 立即休息（菜单栏/设置页） | 立即 `present()` | 推进 |
| 暂停/恢复（菜单栏/设置页） | 停 Timer / 重排 | —— |

## 生命周期集成

| 集成点 | 行为 |
|--------|------|
| `AppServices` | 持有 `standReminder`，与 `modeEngine` 同级 |
| `AppDelegate.applicationDidFinishLaunching` | `standReminder.bootstrap()` |
| `AppDelegate.applicationWillTerminate` | `standReminder.shutdown()` |
| `InkPaperApp` MenuBarExtra | 立即休息 / 暂停/恢复提醒 / 下次提醒时间 |
| `SettingsRootView` | 「提醒」Tab |
| 睡眠唤醒 | 监听 `NSWorkspace.didWakeNotification`，重新对齐调度 |

## 与壁纸模式解耦

- 不复用 `OverlayWallpaperService` 的窗口（层级、属性、用途都不同）。
- 不占用 `DisplayRegistry.onDisplaysChanged` 单回调（ModeEngine 已占用），改用 Combine 观察 `@Published displays`。
- 不调用 `ModeEngine` 任何 API。
