# 图片管线

## 源码

- `InkPaper/Image/ImagePipeline.swift`（静态工具，非 `@MainActor` 实例）

## 校验 `validate`

1. 路径存在、可读
2. 文件大小 ≤ `maxImageBytes`（默认 50MB）
3. ImageIO 读取像素宽高
4. 边长 ≤ `maxImageDimension`（默认 16384）
5. 超限拒绝

## 预览

- `loadThumbnail(path:maxPixelSize:)`：ImageIO 缩略图（默认 512px）
- 设置页预览走缩略图 + 异步加载，**禁止**在 SwiftUI `body` 里 `NSImage(contentsOfFile:)` 读原图

## Overlay 渲染

- `prepareOverlayImages`：按屏解码 + 缩放，供 `Task.detached` 后台调用；跳过无路径的屏（仅原生）；全部跳过则抛错
- `renderedImage`：用 `NSBitmapImageRep` 离屏绘制（避免 `lockFocus` 主线程卡顿）
- 主线程 `OverlayWallpaperService` 只接收已渲染的 `NSImage` 并挂到窗口

## 缓存

- 原图 / 缩略图分缓存，串行队列保护
- 选图后 `invalidateCache()`
