import AppKit

struct WindowFrame {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

enum Screens {
    @MainActor static var names: [String] { NSScreen.screens.map(\.localizedName) }

    /// Picks a display fast enough for `fps` (the menu bar display if it qualifies,
    /// else the fastest one) and returns a phone-shaped window frame on its right side.
    /// The result is in SDL coordinates: points, origin at the top-left of the menu bar display.
    @MainActor
    static func windowFrame(fps: Int, preferredName: String,
                            device: (width: Int, height: Int)?, landscape: Bool = false) -> WindowFrame? {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return nil }

        let target: NSScreen
        if let named = screens.first(where: { $0.localizedName == preferredName }) {
            target = named
        } else {
            let fastEnough = screens.filter { $0.maximumFramesPerSecond >= fps }
            if fastEnough.contains(primary) {
                target = primary
            } else {
                target = fastEnough.max { $0.maximumFramesPerSecond < $1.maximumFramesPerSecond } ?? primary
            }
        }

        let visible = target.visibleFrame
        let size = device ?? (width: 1080, height: 2400)
        let shortSide = Double(min(size.width, size.height))
        let longSide = Double(max(size.width, size.height))
        let width: Double
        let height: Double
        let x: Double
        if landscape {
            // Landscape (usually video): wide window centered on the display.
            width = min(visible.width * 0.75, visible.height * 0.8 * longSide / shortSide).rounded()
            height = (width * shortSide / longSide).rounded()
            x = visible.midX - width / 2
        } else {
            height = (visible.height * 0.88).rounded()
            width = (height * shortSide / longSide).rounded()
            x = visible.maxX - width - 40
        }
        // Leave room above the content for the title bar.
        let top = visible.maxY - (visible.height - height) / 2 - 14
        let y = primary.frame.maxY - top
        return WindowFrame(x: Int(x), y: Int(y), width: Int(width), height: Int(height))
    }

    /// Height of the scrcpy title bar: SDL positions the content area, CGWindowList reports
    /// the whole window.
    static let titleBarHeight = 32

    /// Global frame of the scrcpy window (CG coordinates: origin top-left, y down).
    static func cgFrame(pid: pid_t) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict),
                  rect.width > 100
            else { continue }
            return rect
        }
        return nil
    }

    /// The scrcpy window's current place, as launch arguments.
    static func currentFrame(pid: pid_t) -> WindowFrame? {
        guard let rect = cgFrame(pid: pid) else { return nil }
        return WindowFrame(x: Int(rect.minX), y: Int(rect.minY) + titleBarHeight,
                           width: Int(rect.width), height: Int(rect.height) - titleBarHeight)
    }

    @MainActor
    static func describe() -> String {
        NSScreen.screens.map { "\($0.localizedName) \($0.maximumFramesPerSecond)Hz" }
            .joined(separator: "，")
    }
}
