import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ValidatedImage: Sendable {
    let path: String
    let pixelWidth: Int
    let pixelHeight: Int
    let byteSize: Int64
}

enum ImagePipeline {
    static let allowedContentTypes: [UTType] = [.jpeg, .png, .heic, .tiff, .bmp, .webP, .gif]

    private static let cacheQueue = DispatchQueue(label: "com.ink.InkPaper.imageCache")
    private static var memoryCache: [String: NSImage] = [:]
    private static var thumbnailCache: [String: NSImage] = [:]

    static func validate(path: String, maxBytes: Int64, maxDimension: Int) throws -> ValidatedImage {
        let url = URL(fileURLWithPath: path)
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { throw AppError.imageMissing(path: path) }
        guard fm.isReadableFile(atPath: path) else { throw AppError.imageUnreadable(path: path) }

        let attrs = try fm.attributesOfItem(atPath: path)
        let bytes = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        if bytes > maxBytes {
            throw AppError.imageTooLarge(path: path, bytes: bytes)
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw AppError.imageUndecodable(path: path)
        }
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw AppError.imageUndecodable(path: path)
        }
        let width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        if width <= 0 || height <= 0 {
            throw AppError.imageUndecodable(path: path)
        }
        if width > maxDimension || height > maxDimension {
            throw AppError.imageDimensionTooLarge(path: path, width: width, height: height)
        }

        return ValidatedImage(path: path, pixelWidth: width, pixelHeight: height, byteSize: bytes)
    }

    static func loadNSImage(path: String, maxBytes: Int64, maxDimension: Int) throws -> NSImage {
        if let cached = cachedImage(for: path) {
            return cached
        }
        _ = try validate(path: path, maxBytes: maxBytes, maxDimension: maxDimension)
        guard let image = NSImage(contentsOfFile: path) else {
            throw AppError.imageUndecodable(path: path)
        }
        storeImage(image, for: path)
        return image
    }

    /// 设置页预览用：ImageIO 缩略图，避免把 4K/5K 原图读进 SwiftUI body。
    static func loadThumbnail(path: String, maxPixelSize: Int = 512) -> NSImage? {
        let key = "thumb:\(maxPixelSize):\(path)"
        if let cached = cachedThumbnail(for: key) {
            return cached
        }
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        storeThumbnail(image, for: key)
        return image
    }

    static func renderedImage(
        from image: NSImage,
        targetSize: CGSize,
        scaleMode: ScaleMode,
        fitBackground: NSColor
    ) -> NSImage {
        let width = max(1, Int(targetSize.width.rounded()))
        let height = max(1, Int(targetSize.height.rounded()))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return image
        }
        rep.size = targetSize

        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = context
            fitBackground.setFill()
            NSBezierPath(rect: CGRect(origin: .zero, size: targetSize)).fill()

            let imageSize = image.size
            if imageSize.width > 0, imageSize.height > 0 {
                let drawRect = drawRect(for: imageSize, target: targetSize, mode: scaleMode)
                image.draw(in: drawRect, from: .zero, operation: .copy, fraction: 1.0)
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        let output = NSImage(size: targetSize)
        output.addRepresentation(rep)
        return output
    }

    /// 在后台准备每屏渲染结果，主线程只负责挂窗。
    static func prepareOverlayImages(
        config: AppConfig,
        displays: [DisplayInfo]
    ) throws -> [String: NSImage] {
        var result: [String: NSImage] = [:]
        for display in displays {
            guard let path = config.imagePath(forDisplayID: display.id) else {
                throw AppError.noImageConfigured
            }
            let source = try loadNSImage(
                path: path,
                maxBytes: config.maxImageBytes,
                maxDimension: config.maxImageDimension
            )
            let bg = NSColor(
                calibratedRed: config.fitBackgroundColor.red,
                green: config.fitBackgroundColor.green,
                blue: config.fitBackgroundColor.blue,
                alpha: config.fitBackgroundColor.alpha
            )
            result[display.id] = renderedImage(
                from: source,
                targetSize: display.frame.size,
                scaleMode: config.scaleMode,
                fitBackground: bg
            )
        }
        return result
    }

    static func invalidateCache() {
        cacheQueue.sync {
            memoryCache.removeAll()
            thumbnailCache.removeAll()
        }
    }

    static func invalidate(path: String) {
        cacheQueue.sync {
            memoryCache.removeValue(forKey: path)
            let keys = thumbnailCache.keys.filter { $0.hasSuffix(path) }
            for key in keys {
                thumbnailCache.removeValue(forKey: key)
            }
        }
    }

    private static func drawRect(for imageSize: CGSize, target: CGSize, mode: ScaleMode) -> CGRect {
        switch mode {
        case .stretch:
            return CGRect(origin: .zero, size: target)
        case .center:
            return CGRect(
                x: (target.width - imageSize.width) / 2,
                y: (target.height - imageSize.height) / 2,
                width: imageSize.width,
                height: imageSize.height
            )
        case .fit:
            let scale = min(target.width / imageSize.width, target.height / imageSize.height)
            let w = imageSize.width * scale
            let h = imageSize.height * scale
            return CGRect(x: (target.width - w) / 2, y: (target.height - h) / 2, width: w, height: h)
        case .fill:
            let scale = max(target.width / imageSize.width, target.height / imageSize.height)
            let w = imageSize.width * scale
            let h = imageSize.height * scale
            return CGRect(x: (target.width - w) / 2, y: (target.height - h) / 2, width: w, height: h)
        }
    }

    private static func cachedImage(for path: String) -> NSImage? {
        cacheQueue.sync { memoryCache[path] }
    }

    private static func storeImage(_ image: NSImage, for path: String) {
        cacheQueue.sync { memoryCache[path] = image }
    }

    private static func cachedThumbnail(for key: String) -> NSImage? {
        cacheQueue.sync { thumbnailCache[key] }
    }

    private static func storeThumbnail(_ image: NSImage, for key: String) {
        cacheQueue.sync { thumbnailCache[key] = image }
    }
}
