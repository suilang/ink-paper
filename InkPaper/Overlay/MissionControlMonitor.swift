import AppKit
import CoreGraphics
import Foundation

/// Detects Mission Control via Dock's layer-18 fullscreen surfaces.
/// (Verified on this machine: present while MC is open, absent otherwise.
/// Layer-20 alone is NOT reliable — Dock keeps a layer-20 hit surface even when MC is off.)
enum MissionControlDetector {
    static func isActive() -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        for entry in list {
            let owner = entry[kCGWindowOwnerName as String] as? String ?? ""
            if owner == "Mission Control" || owner == "调度中心" || owner == "任务控制" {
                return true
            }

            let isDock = owner == "Dock" || owner == "程序坞"
            guard isDock else { continue }

            let title = entry[kCGWindowName as String] as? String ?? ""
            if title.hasPrefix("Wallpaper") { continue }

            let layer = entry[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 18 else { continue }

            guard let bounds = entry[kCGWindowBounds as String] as? [String: Any] else { continue }
            let width = bounds["Width"] as? CGFloat ?? 0
            let height = bounds["Height"] as? CGFloat ?? 0
            for screen in NSScreen.screens {
                if width >= screen.frame.width * 0.9, height >= screen.frame.height * 0.9 {
                    return true
                }
            }
        }
        return false
    }
}

@MainActor
final class MissionControlMonitor {
    var onActiveChange: ((Bool) -> Void)?

    private var timer: Timer?
    private(set) var isActive = false

    func start(interval: TimeInterval = 0.12) {
        stop()
        isActive = MissionControlDetector.isActive()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isActive = false
    }

    private func tick() {
        let now = MissionControlDetector.isActive()
        guard now != isActive else { return }
        isActive = now
        onActiveChange?(now)
    }
}
