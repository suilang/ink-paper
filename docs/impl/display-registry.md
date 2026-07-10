# 显示器注册表

## 源码

- `InkPaper/Display/DisplayInfo.swift`
- `InkPaper/Display/DisplayRegistry.swift`

## 稳定 ID

优先：`NSScreen.deviceDescription["NSScreenNumber"]` → `CGDirectDisplayID` 字符串。  
回退：几何签名 `geo:x_y_w_h`（排列变化时不稳定，分屏 map 可能失效）。

## 事件

监听 `NSApplication.didChangeScreenParametersNotification`：

1. `refresh()` 重建 `displays`
2. 若 ID 集合变化 → 设置 `lastChangeMessage = "检测到显示器变更，请确认分屏配置"`
3. 回调 `onDisplaysChanged`（ModeEngine 用于重建 overlay）

## DisplayInfo 字段

`id`、`localizedName`、`frame`、`scaleFactor`、`isMain`、`screenNumber`。
