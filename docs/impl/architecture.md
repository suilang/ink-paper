# 架构总览

## 技术栈

- Swift 5 + SwiftUI App 生命周期（`InkPaperApp`）
- AppKit（系统壁纸、底层窗口、激活策略）
- 无第三方依赖

## 目录与模块

```
InkPaper/
  App/           InkPaperApp、AppDelegate、AppServices、MenuBarExtra
  Config/        AppConfig + ConfigStore
  Mode/          ModeEngine（编排中心）
  SystemWallpaper/  模式 A
  Overlay/       模式 B
  Display/       屏幕注册表
  Image/         校验与缩放
  Health/        健康检查
  Settings/      SettingsRootView
  Support/       错误类型、通知
  Resources/     Info.plist
```

## 依赖方向

```
InkPaperApp (SwiftUI)
  ├─ AppServices.shared
  │    ├─ ConfigStore
  │    ├─ DisplayRegistry
  │    └─ ModeEngine → Image / SystemWallpaper / Overlay / Health
  ├─ Window(settings) → SettingsRootView
  ├─ MenuBarExtra → 菜单操作
  └─ AppDelegate（activationPolicy、bootstrap、打开/兜底设置窗）
```

规则：

- UI 只通过 `AppServices` / `ModeEngine` / `ConfigStore` / `DisplayRegistry` 操作。
- `ModeEngine` 是唯一允许同时触达模式 A/B 服务的编排层，负责互斥与回滚。

## 运行时状态

| 状态 | 持有者 | 说明 |
|------|--------|------|
| `AppConfig` | `ConfigStore` | 持久化用户偏好 |
| `activeMode` | `ModeEngine` | `system` / `overlay` / `nil` |
| `displays` | `DisplayRegistry` | 当前 `NSScreen` 快照 |
| overlay 窗口表 | `OverlayWallpaperService` | `displayID → NSWindow` |

## 模式互斥

- 进入任一模式前：`ModeEngine.stopActiveMode()` 会停掉 overlay 窗口。
- 系统壁纸模式无运行时托管资源；退出应用时**不**还原系统壁纸。
- 退出应用时：`shutdown()` 销毁全部 overlay 窗口。
