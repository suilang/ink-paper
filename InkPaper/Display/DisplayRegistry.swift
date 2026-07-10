import AppKit
import Foundation

@MainActor
final class DisplayRegistry: ObservableObject {
    @Published private(set) var displays: [DisplayInfo] = []
    @Published private(set) var lastChangeMessage: String?

    /// Fired only when display identity / geometry / scale actually changes.
    /// Mission Control often posts `didChangeScreenParametersNotification` without
    /// changing screens — those must not tear down overlay windows.
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

    /// Fingerprint used to ignore spurious screen-parameter notifications.
    private func fingerprint(of displays: [DisplayInfo]) -> [String] {
        displays
            .map { d in
                "\(d.id)|\(d.frame.origin.x)|\(d.frame.origin.y)|\(d.frame.size.width)|\(d.frame.size.height)|\(d.scaleFactor)"
            }
            .sorted()
    }

    @objc private func screenParamsChanged() {
        let before = fingerprint(of: displays)
        let beforeIDs = Set(displays.map(\.id))
        refresh()
        let after = fingerprint(of: displays)
        let afterIDs = Set(displays.map(\.id))

        guard before != after else { return }

        if beforeIDs != afterIDs {
            lastChangeMessage = "检测到显示器变更，请确认分屏配置"
        }
        onDisplaysChanged?()
    }
}
