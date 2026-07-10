# 系统壁纸（模式 A）

## 源码

- `InkPaper/SystemWallpaper/SystemWallpaperService.swift`

## 设置

- API：`NSWorkspace.shared.setDesktopImageURL(_:for:options:)`
- 选项：`imageScaling = scaleProportionallyUpOrDown`，`allowClipping = true`
- 对每个有图的显示器分别设置；**「仅原生」屏跳过**（保留系统当前壁纸）
- 若没有任何屏被设置则抛 `noImageConfigured`
- 校验走 `ImagePipeline.validate`
- **设置前**先 `probeDesktopLock()`；若锁定直接抛 `systemWallpaperUnavailable`
- **设置后**异步回读当前壁纸路径（约 0.8s）；与目标不一致则判失败（覆盖“API 成功但被 MDM 打回”）

## 读取

- `NSWorkspace.shared.desktopImageURL(for:)`

## MDM / 托管锁定探测 `probeDesktopLock()`

读取这些位置（本机实测存在）：

| 路径 | 关注键 |
|------|--------|
| `/Library/Managed Preferences/com.apple.desktop.plist` | `locked`、`override-picture-path`、`Background` |
| `/Library/Managed Preferences/<user>/com.apple.desktop.plist` | 同上 |
| `/Library/Managed Preferences/.../com.apple.applicationaccess.plist` | `allowWallpaperModification == false` |

另：若 CFPreferences 能读到 `override-picture-path` 且托管文件存在，也计入锁定。

结果缓存于 `lastLockProbe`，诊断项 **A02** 展示 `summary`。

当前开发机示例：

- `locked = true`
- `override-picture-path = /Library/Desktop Pictures/Desktop201810.JPG`

## 自动模式行为

`ModeEngine.applyPreferredMode` 在 `preferredMode == auto` 时：

1. 先 `probeDesktopLock()`
2. 锁定且 `autoFallbackToOverlay` → 直接 `switchTo(.overlay)` 并通知
3. 未锁定再走健康报告 / 试设系统壁纸；失败同样可降级

## 备份

| 项 | 值 |
|----|-----|
| 文件 | `~/Library/Application Support/InkPaper/system-wallpaper-backup.json` |
| 内容 | `[{ displayID, path }]` |

## 深度检查

- `deepWritabilityCheck`：先看锁定，再对当前路径试写并回读校验（异步）
