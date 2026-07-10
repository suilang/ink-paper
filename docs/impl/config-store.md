# 配置存储（Config Store）

## 源码

- `InkPaper/Config/AppConfig.swift`
- `InkPaper/Config/ConfigStore.swift`

## 持久化

| 项 | 值 |
|----|-----|
| 路径 | `~/Library/Application Support/InkPaper/config.json` |
| 格式 | JSON（pretty + sorted keys，日期 ISO8601） |
| 写入 | `update` 后内存立即生效；磁盘写入在后台队列异步完成 |
| 损坏处理 | 复制为 `config.corrupt.<timestamp>.json`，回退 `AppConfig.default` 并重写 |

## 硬约束（写入时强制）

无论调用方传入什么值，`ConfigStore.update` / `replace` 都会强制：

- `ignoreMouseEvents = true`
- `hideOnAppQuit = true`

## 主要字段（与需求文档逻辑名对应）

| 字段 | 默认 | 行为 |
|------|------|------|
| `preferredMode` | `auto` | 自动 / 强制 system / 强制 overlay |
| `wallpaperEnabled` | `false` | **是否启用铺桌面**（与选图分离；见 interaction-flow） |
| `lastMode` | `system` | 上次成功应用的模式 |
| `imagePath` | `nil` | 全局图片路径（选图，不直接等于启用） |
| `perDisplayEnabled` | `false` | 分屏独立图片 |
| `perDisplayMap` | `{}` | `displayID → path`（仅真实路径） |
| `perDisplayNativeIDs` | `[]` | 显式「仅原生」的显示器集合；不删 map 中原路径 |
| `scaleMode` | `fill` | fill / fit / stretch / center |
| `fitBackgroundColor` | 黑 | fit 留边色 |
| `applyToAllSpaces` | `true` | overlay 是否 `canJoinAllSpaces` |
| `autoFallbackToOverlay` | `true` | 模式 A 失败自动降级 |
| `notifyOnFallback` | `true` | 降级发通知 |
| `backupSystemWallpaperBeforeSwitch` | `true` | 切换前备份 |
| `checkOnLaunch` | `true` | 启动健康检查 |
| `maxImageBytes` | 50MB | 校验上限 |
| `maxImageDimension` | 16384 | 边长上限 |

## 分屏路径解析

`AppConfig.imagePath(forDisplayID:)`（仅当 `perDisplayEnabled`）：

1. 在 `perDisplayNativeIDs` 中（或旧配置空字符串哨兵）→ `nil`（该屏不覆盖）  
2. map 中有非空路径 → 用分屏路径  
3. 键不存在 → 全局 `imagePath`

`usesNativeWallpaperOnly(forDisplayID:)`：分屏开启且在 native 集合中。

`hasUsableWallpaperImage(displayIDs:)`：至少有一块屏当前能解析出非空路径。

`hasWallpaperImageAssets()`：仍有全局图或非空分屏路径（含被仅原生暂时不用的路径）；用于判断是否该自动停用。

解码时会把旧的 `perDisplayMap[id] = ""` 迁入 `perDisplayNativeIDs` 并清掉空串。

## 配置迁移

旧 `config.json` 无 `wallpaperEnabled` 时：若 `overlayEnabled == true` 则视为已启用，否则 `false`。

## 登录项

`applyLaunchAtLogin()` 在 macOS 13+ 使用 `SMAppService.mainApp` register/unregister。  
由设置页「登录时启动」开关触发。
