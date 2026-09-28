# 设置页与菜单栏

## 源码

- `InkPaper/Settings/SettingsRootView.swift`（TabView 骨架 + statusBar + 共享状态）
- `InkPaper/Settings/SettingsSharedState.swift`（跨页共享 `@State` 与 helper）
- `InkPaper/Settings/Pages/WallpaperModePage.swift`（壁纸+模式融合页）
- `InkPaper/Settings/Pages/GeneralPage.swift`
- `InkPaper/Settings/Pages/DiagnosticsPage.swift`
- `InkPaper/Settings/Pages/ReminderPage.swift`（活动提醒设置）
- `InkPaper/Settings/Pages/AboutPage.swift`
- `InkPaper/Settings/Components/DisplayThumbnail.swift`
- `InkPaper/App/InkPaperApp.swift`
- `InkPaper/App/AppDelegate.swift`

## 交互总纲

详见 **[interaction-flow.md](./interaction-flow.md)**（选图 / 启用分离、反馈规范、验收清单）。

## Tab 结构

壁纸与模式 · 通用 · 诊断 · 提醒 · 关于（原「壁纸」「模式」两页已融合为「壁纸与模式」；无独立「显示器」Tab，分屏管理在融合页内）。

## 关于页布局（当前）

1. **应用头图**：App Icon + 名称 + 简介 + 版本/构建号（macOS 13+）
2. **信息**：MIT 协议、GitHub 项目主页链接
3. **赞助**：说明文案 + 微信赞赏码（资源名 `WeChatPay`，源图 `docs/assets/wechat-pay.png`）

## 壁纸与模式融合页布局（当前）

1. **启用区（顶部）**：`启用壁纸` 开关 + 状态徽章 + 说明
2. **模式分区**：偏好模式 Picker、自动降级/降级通知/备份/所有 Space 开关、系统壁纸策略（可写/锁定 MDM）、当前模式、按偏好应用/切系统/切底层/停用 按钮
3. 分屏开关（说明：可单独选图，或指定某屏仅用原生壁纸）
4. 显示器变更提示（若有 `lastChangeMessage`）
5. 分屏列表（开启时）：每行缩略图 + 选图 / 改用兜底图或恢复覆盖 / 仅原生壁纸；底部可刷新显示器列表
6. 全局图 / 兜底图：大预览 + 选图/移除
7. 缩放（已启用时改策略/留边色立即重铺）
8. 清除全部已选图（会自动停用）

原独立的「模式」Tab 已并入本页第 2 分区。

## 分屏三态（`perDisplayEnabled == true`）

| 状态 | 配置 | 桌面行为 |
|------|------|----------|
| 独立图 | `perDisplayMap` 非空路径，且不在 native 集合 | 该屏铺该图 |
| 使用兜底 | map 无键，且不在 native 集合 | 该屏用全局 `imagePath` |
| 仅原生壁纸 | `perDisplayNativeIDs` 含该屏（保留原分屏路径） | **不覆盖** |

「仅原生」不删已选分屏图。按钮「恢复覆盖」取消 native 标记并立即重铺；「改用兜底图」在非 native 且有分屏图时清除分屏路径。

## 反馈规范摘要

| 动作 | 桌面是否变化 | 反馈 |
|------|--------------|------|
| 未启用时选图 | 否 | 缩略图 +「尚未启用」 |
| 打开启用 | 是 | busy →「已启用：模式」 |
| 关闭启用 | 停 overlay | 「已停用（图片仍保留）」 |
| 已启用下选图/换图/改缩放/分屏三态 | 是 | 立即 `updateDesktopAsync` |
| 清除全部图 | 停用 | 自动 `disableWallpaperAsync` |

## 提醒页布局（当前）

1. **启用区**：`启用活动提醒` 开关 + 状态徽章（未启用/运行中/已延期/已暂停/休息中）
2. **提醒间隔**：Picker 10/15/20/25 分钟
3. **展示方式**：单选 仅主屏 / 主屏+主外接屏（无外接屏时自动退化为单屏）
4. **休息时长**：自动交替开关（默认开）；关闭后可选固定 20s/60s
5. **延期**：固定 5 分钟（说明文案）
6. **操作**：立即休息 / 暂停/恢复提醒；下次提醒时间

活动提醒的引擎与提示窗实现详见 [stand-reminder.md](./stand-reminder.md)。

## 模式操作 / 菜单栏

- 显式切换模式会 **隐含启用**
- 菜单栏提供：启用 / 停用壁纸、切换系统/底层模式、**立即休息 / 暂停/恢复活动提醒**、运行诊断、退出
- 改图在设置里直接生效（无单独「更新到桌面」）
