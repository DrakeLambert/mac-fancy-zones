import AppKit

/// Click-through overlay covering one screen, kept at normal window level and ordered directly
/// below the dragged window so the dragged window stays fully visible on top.
final class ZoneOverlay {
    let screen: NSScreen
    private let window: NSWindow
    private let view = ZonesView()

    init(screen: NSScreen) {
        self.screen = screen
        window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .normal
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.contentView = view
    }

    /// `zoneRects` in AppKit global (bottom-left) coordinates.
    func update(zoneRects: [CGRect], highlighted: Set<Int>) {
        view.rects = zoneRects.map { $0.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY) }
        view.highlighted = highlighted
        view.needsDisplay = true
    }

    func show(below windowID: CGWindowID) { window.order(.below, relativeTo: Int(windowID)) }
    func hide() { window.orderOut(nil) }}

private final class ZonesView: NSView {
    var rects: [CGRect] = []
    var highlighted: Set<Int> = []

    override func draw(_ dirty: NSRect) {
        for (i, r) in rects.enumerated() {
            let on = highlighted.contains(i)
            (on ? NSColor.controlAccentColor.withAlphaComponent(0.6) : NSColor.white.withAlphaComponent(0.2)).setFill()
            let path = NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8)
            path.fill()
            (on ? NSColor.controlAccentColor : NSColor.white.withAlphaComponent(0.5)).setStroke()
            path.lineWidth = on ? 3 : 1.5
            path.stroke()
        }
    }
}
