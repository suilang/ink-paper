# 模式引擎（Mode Engine）

## 源码

- `InkPaper/Mode/ModeEngine.swift`

## 职责

- 按偏好决定目标模式并应用
- **启用 / 停用** 与选图分离（`wallpaperEnabled`）
- 模式切换事务、MDM 降级、屏变重建
- `isBusy` / `statusMessage` / `lastError` 反馈

交互规范见 [interaction-flow.md](./interaction-flow.md)。

## 启动：`bootstrap()`

1. 可选健康检查
2. **仅当** `wallpaperEnabled == true` 时 `applyPreferredModeAsync()`
3. 未启用则只提示「壁纸未启用」

## 对外异步 API

| 方法 | 行为 |
|------|------|
| `enableWallpaperAsync()` | `wallpaperEnabled=true` → `applyPreferredMode` |
| `disableWallpaperAsync()` | 停 overlay；`wallpaperEnabled=false`；**不删图** |
| `updateDesktopAsync()` | 要求已启用；按当前/偏好重铺（设置页已启用时选图等会自动调用；菜单栏无单独入口）。忙碌时合并为最新一次请求，不丢后续操作。 |
| `applyPreferredModeAsync()` | 隐含启用后按偏好应用 |
| `switchToAsync(_:)` | 隐含启用后切到指定模式 |
| `reapplyCurrentAsync()` | 转调 `updateDesktopAsync()` |
| `syncOverlayDisplaysAsync()` | overlay 已激活时：预渲染后 `applyPreparedImages`（不先 stop） |

## `applyPreferredMode`（auto）

1. `probeDesktopLock()`：锁定且允许降级 → overlay
2. 否则健康报告 / 试 system；失败可降级

## 健康检查

- `runHealthCheck` 为 async
- A02 使用真实 `probeDesktopLock().summary`

## 屏变

`DisplayRegistry.onDisplaysChanged` 仅在显示器指纹变化时触发。  
overlay 激活且 `restoreOnDisplayChange` 时走 `syncOverlayDisplaysAsync()`，不先 `stopActiveMode`。

## 分屏「仅原生」

`ensureImagesReady` 允许「有图资源但当前全屏仅原生」；预渲染可返回空表（拆光覆盖窗）。  
系统壁纸 apply 在 0 屏可写时视为成功。自动停用只看 `hasWallpaperImageAssets()`，不因暂时全原生而关启用。
