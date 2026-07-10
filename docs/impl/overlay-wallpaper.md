# 底层窗口壁纸（模式 B）

## 源码

- `InkPaper/Overlay/OverlayWallpaperService.swift`

## 窗口属性（实际）

| 属性 | 值 |
|------|-----|
| styleMask | `.borderless` |
| level | `CGWindowLevelForKey(.desktopWindow)` |
| `ignoresMouseEvents` | `true` |
| `canBecomeKey` / `canBecomeMain` | `false` |
| collectionBehavior | `.canJoinAllSpaces`（可配）、`.stationary`、`.ignoresCycle` |
| frame | 对应 `NSScreen.frame` |

## 渲染分工

1. 后台：`ImagePipeline.prepareOverlayImages` 产出 `[displayID: NSImage]`
2. 主线程：`start` / `applyPreparedImages` 创建或更新窗口并赋值 `OverlayImageView.image`

这样切换到底层窗口时，设置页不会因全屏位图绘制而卡死。

## 生命周期

- `start` → `isActive = true` → 应用预渲染图
- `stop` / 退出：销毁全部窗口
- 屏变：`ModeEngine` 调 `reapplyCurrentAsync()` 重建
