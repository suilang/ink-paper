import AppKit
import Foundation

@MainActor
final class DisplayRegistry: ObservableObject {
    @Published private(set) var displays: [DisplayInfo] = []
    @Published private(set) var lastChangeMessage: String?

    var onDisplaysChanged: (() -> Void)?

    init() {
        refresh()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParamsChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func refresh() {
        let screens = NSScreen.screens
        let mainID = screens.first(where: { $0 == NSScreen.main }).map { DisplayIDFactory.stableID(for: $0) }
        displays = screens.map { screen in
            let id = DisplayIDFactory.stableID(for: screen)
            return DisplayInfo(
                id: id,
                localizedName: screen.localizedName,
                frame: screen.frame,
                scaleFactor: screen.backingScaleFactor,
                isMain: id == mainID,
                screenNumber: DisplayIDFactory.screenNumber(for: screen)
            )
        }
    }

    func screen(forDisplayID id: String) -> NSScreen? {
        NSScreen.screens.first { DisplayIDFactory.stableID(for: $0) == id }
    }

    @objc private func screenParamsChanged() {
        let before = Set(displays.map(\.id))
        refresh()
        let after = Set(displays.map(\.id))
        if before != after {
            lastChangeMessage = "检测到显示器变更，请确认分屏配置"
        }
        onDisplaysChanged?()
    }
}
