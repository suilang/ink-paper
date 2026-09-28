import AppKit
import SwiftUI

/// 分屏行缩略图。异步加载，避免在 body 里读大图卡死主线程。
struct DisplayThumbnail: View {
    let path: String?
    var nativeOnly: Bool = false
    @State private var image: NSImage?

    var body: some View {
        Group {
            if nativeOnly {
                Text("原生")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Text(path == nil ? "无图" : "…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .clipped()
        .onAppear { load() }
        .onChange(of: path) { _ in load() }
        .onChange(of: nativeOnly) { _ in
            if nativeOnly { image = nil }
        }
    }

    private func load() {
        if nativeOnly {
            image = nil
            return
        }
        guard let path else {
            image = nil
            return
        }
        Task.detached(priority: .utility) {
            let thumb = ImagePipeline.loadThumbnail(path: path, maxPixelSize: 256)
            await MainActor.run {
                image = thumb
            }
        }
    }
}
