# 底层窗口壁纸（模式 B）

## 源码

- `InkPaper/Overlay/OverlayWallpaperService.swift`
- `InkPaper/Overlay/MissionControlMonitor.swift`

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

1. 后台：`ImagePipeline.prepareOverlayImages` 产出 `[displayID: NSImage]`（跳过「仅原生」屏；若结果为空则抛 `noImageConfigured`）
2. 主线程：`start` / `applyPreparedImages` 创建或更新窗口并赋值 `OverlayImageView.image`

## 生命周期

- `start` → `isActive = true` → 应用预渲染图 → 启动 Mission Control 监视
- `applyPreparedImages`：按当前屏增删/更新窗口，不先 `stop`；**无图的屏销毁覆盖窗**（原生-only）
- `stop` / 退出：停监视并销毁全部窗口
- 屏变：`ModeEngine.syncOverlayDisplaysAsync()` 原地同步

## 副屏 × Mission Control

外接屏在任务中心合成时容易短暂露出 Dock 真壁纸。策略改为：

1. 轮询检测 Dock 的 **layer=18 全屏窗**（任务中心开启时出现；平时没有；layer=20 不可靠）
2. 进入任务中心：对 **非主屏**（`CGMainDisplayID()`）overlay 执行 `orderOut`（不销毁）→ 稳定显示原始壁纸
3. 退出任务中心：再 `orderBack` 盖回

主屏保持原样（不藏）。

## 左右滑 Space 为何也会闪

与任务中心同类：Space 切换动画时 WindowServer 会重组每块屏的桌面层。外屏通常没有访达 Desktop 窗，合成瞬间只露出 Dock 真壁纸，随后 overlay 再回来。`canJoinAllSpaces` 不能消除这段合成间隙。当前不对左右滑做藏窗（事后藏会更闪）。
