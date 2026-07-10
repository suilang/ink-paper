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
2. 用指纹（`id` + `frame` + `scaleFactor`）与变更前比较；**相同则直接返回**（过滤 Mission Control 等误触发）
3. 若 ID 集合变化 → 设置 `lastChangeMessage = "检测到显示器变更，请确认分屏配置"`
4. 仅指纹变化时回调 `onDisplaysChanged`（ModeEngine 轻量同步 overlay，不先销毁窗口）

## DisplayInfo 字段

`id`、`localizedName`、`frame`、`scaleFactor`、`isMain`、`screenNumber`。
