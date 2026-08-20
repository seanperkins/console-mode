import AppKit

enum ScreenLocator {
    static func screenForMouse() -> NSScreen {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    static func metrics(for screen: NSScreen) -> ScreenMetrics {
        let frame = screen.visibleFrame
        return ScreenMetrics(
            visibleOriginX: frame.origin.x,
            visibleOriginY: frame.origin.y,
            visibleWidth: frame.width,
            visibleHeight: frame.height
        )
    }
}
