import AppKit
import Foundation

struct DisplayInfo: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let localizedName: String
    let frame: CGRect
    let scaleFactor: CGFloat
    let isMain: Bool
    let screenNumber: CGDirectDisplayID

    var resolutionDescription: String {
        let w = Int(frame.width)
        let h = Int(frame.height)
        let scale = scaleFactor == 1 ? "" : " @\(String(format: "%.0f", scaleFactor))x"
        return "\(w)×\(h)\(scale)"
    }
}

enum DisplayIDFactory {
    static func stableID(for screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            let displayID = CGDirectDisplayID(number.uint32Value)
            return String(displayID)
        }
        // Fallback: geometric signature (less stable across rearrange)
        let f = screen.frame
        return String(format: "geo:%.0f_%.0f_%.0f_%.0f", f.origin.x, f.origin.y, f.width, f.height)
    }

    static func screenNumber(for screen: NSScreen) -> CGDirectDisplayID {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return CGDirectDisplayID(number.uint32Value)
        }
        return 0
    }
}
