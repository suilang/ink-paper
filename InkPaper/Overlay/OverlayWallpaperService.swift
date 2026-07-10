import AppKit
import CoreGraphics
import Foundation

/// Borderless desktop-level wallpaper window. Non-activating, click-through.
final class OverlayWallpaperWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        configure(for: screen)
    }

    func configure(for screen: NSScreen) {
        setFrame(screen.frame, display: true)
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        orderBack(nil)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class OverlayImageView: NSView {
    var image: NSImage? {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        guard let image else { return }
        image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1.0)
    }
}

@MainActor
final class OverlayWallpaperService {
    private var windows: [String: OverlayWallpaperWindow] = [:]
    private var imageViews: [String: OverlayImageView] = [:]
    private var secondaryHiddenForMissionControl = false
    private let missionControlMonitor = MissionControlMonitor()
    private weak var displayRegistry: DisplayRegistry?
    private(set) var isActive = false

    var activeWindowCount: Int { windows.count }

    init() {
        missionControlMonitor.onActiveChange = { [weak self] active in
            self?.handleMissionControlActiveChange(active)
        }
    }

    func start(
        config: AppConfig,
        displays: [DisplayInfo],
        registry: DisplayRegistry,
        imagesByDisplayID: [String: NSImage]
    ) throws {
        guard !displays.isEmpty else { throw AppError.noDisplays }
        isActive = true
        displayRegistry = registry
        try applyPreparedImages(
            config: config,
            displays: displays,
            registry: registry,
            imagesByDisplayID: imagesByDisplayID
        )
        missionControlMonitor.start()
        // Sync once in case MC is already open when overlay starts.
        handleMissionControlActiveChange(MissionControlDetector.isActive())
    }

    func applyPreparedImages(
        config: AppConfig,
        displays: [DisplayInfo],
        registry: DisplayRegistry,
        imagesByDisplayID: [String: NSImage]
    ) throws {
        guard isActive else { return }
        displayRegistry = registry

        let activeIDs = Set(displays.map(\.id))
        for id in windows.keys where !activeIDs.contains(id) {
            destroyWindow(id: id)
        }

        for display in displays {
            guard let screen = registry.screen(forDisplayID: display.id) else { continue }
            // 无预渲染图 = 该屏仅用原生壁纸：拆掉覆盖窗（若有），不抛错。
            guard let rendered = imagesByDisplayID[display.id] else {
                destroyWindow(id: display.id)
                continue
            }

            let window: OverlayWallpaperWindow
            let view: OverlayImageView
            if let existing = windows[display.id], let existingView = imageViews[display.id] {
                window = existing
                view = existingView
                window.configure(for: screen)
            } else {
                window = OverlayWallpaperWindow(screen: screen)
                view = OverlayImageView(frame: CGRect(origin: .zero, size: display.frame.size))
                window.contentView = view
                windows[display.id] = window
                imageViews[display.id] = view
            }

            window.ignoresMouseEvents = true
            if config.applyToAllSpaces {
                window.collectionBehavior.insert(.canJoinAllSpaces)
            } else {
                window.collectionBehavior.remove(.canJoinAllSpaces)
            }

            view.frame = CGRect(origin: .zero, size: display.frame.size)
            view.image = rendered

            let isPrimary = display.screenNumber == CGMainDisplayID()
            if secondaryHiddenForMissionControl, !isPrimary {
                window.orderOut(nil)
            } else {
                window.orderBack(nil)
            }
        }
    }

    func stop() {
        missionControlMonitor.stop()
        secondaryHiddenForMissionControl = false
        displayRegistry = nil
        isActive = false
        for id in Array(windows.keys) {
            destroyWindow(id: id)
        }
    }

    func destroyWindow(id: String) {
        windows[id]?.orderOut(nil)
        windows[id]?.close()
        windows.removeValue(forKey: id)
        imageViews.removeValue(forKey: id)
    }

    func canCreateDesktopLevelWindow() -> Bool {
        true
    }

    /// Hide secondary-display overlays while Mission Control is open (show real wallpaper).
    /// Primary display keeps its overlay (already stable / non-flashing there).
    private func handleMissionControlActiveChange(_ active: Bool) {
        guard isActive else { return }
        secondaryHiddenForMissionControl = active
        let primaryID = CGMainDisplayID()
        for (id, window) in windows {
            guard let screenNumber = displayRegistry?.displays.first(where: { $0.id == id })?.screenNumber
                    ?? UInt32(id) else { continue }
            let isPrimary = screenNumber == primaryID
            guard !isPrimary else { continue }
            if active {
                window.orderOut(nil)
            } else {
                window.orderBack(nil)
            }
        }
    }
}
