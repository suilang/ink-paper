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
| `updateDesktopAsync()` | 要求已启用；按当前/偏好重铺 |
| `applyPreferredModeAsync()` | 隐含启用后按偏好应用 |
| `switchToAsync(_:)` | 隐含启用后切到指定模式 |
| `reapplyCurrentAsync()` | 转调 `updateDesktopAsync()` |

## `applyPreferredMode`（auto）

1. `probeDesktopLock()`：锁定且允许降级 → overlay
2. 否则健康报告 / 试 system；失败可降级

## 健康检查

- `runHealthCheck` 为 async
- A02 使用真实 `probeDesktopLock().summary`
