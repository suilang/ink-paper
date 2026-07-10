# 设置页与菜单栏

## 源码

- `InkPaper/Settings/SettingsRootView.swift`
- `InkPaper/App/InkPaperApp.swift`
- `InkPaper/App/AppDelegate.swift`

## 交互总纲

详见 **[interaction-flow.md](./interaction-flow.md)**（选图 / 启用分离、反馈规范、验收清单）。

## Tab 结构

壁纸 · 模式 · 通用 · 诊断 · 关于（无独立「显示器」Tab；分屏管理在壁纸页）。

## 关于页布局（当前）

1. **应用头图**：App Icon + 名称 + 简介 + 版本/构建号（macOS 13+）
2. **信息**：MIT 协议、GitHub 项目主页链接
3. **赞助**：说明文案 + 微信赞赏码（资源名 `WeChatPay`，源图 `docs/assets/wechat-pay.png`）

## 壁纸页布局（当前）

1. **启用区（顶部）**：`启用壁纸` 开关 + 状态徽章 + 说明  
2. 分屏开关（说明：可单独选图，或指定某屏仅用原生壁纸）  
3. 显示器变更提示（若有 `lastChangeMessage`）  
4. 分屏列表（开启时）：每行缩略图 + 选图 / 改用兜底图或恢复覆盖 / 仅原生壁纸；底部可刷新显示器列表  
5. 全局图 / 兜底图：大预览 + 选图/移除  
6. 缩放（已启用时改策略/留边色立即重铺）  
7. 清除全部已选图（会自动停用）

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

## 模式页 / 菜单栏

- 显式切换模式会 **隐含启用**
- 菜单栏提供：启用 / 停用（无单独「更新到桌面」；改图在设置里直接生效）
