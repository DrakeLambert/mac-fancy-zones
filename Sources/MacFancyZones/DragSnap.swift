import AppKit
import FancyZonesCore

final class DragSnap {
    var config: Config
    private var monitors: [Any] = []
    private var target: (el: AXUIElement, id: CGWindowID)?
    private var downPoint = CGPoint.zero            // AppKit coords
    private var timer: Timer?
    private var overlay: ZoneOverlay?
    private var swept: [Int] = []                   // ordered, unique zone indices

    private var primaryHeight: CGFloat { NSScreen.screens[0].frame.height }

    init(config: Config) { self.config = config }

    func start() {
        // Don't let one hung app block the main thread inside an AX call.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25)
        monitor(.leftMouseDown) { [weak self] in self?.down() }
        monitor(.leftMouseUp) { [weak self] in self?.up() }
        // Releasing the button while Ctrl is held can arrive as a right-button release (Ctrl-click = right-click).
        monitor(.rightMouseUp) { [weak self] in self?.up() }
    }

    /// Global monitors miss events delivered to our own windows (e.g. a drop over Settings), so also install a local one.
    private func monitor(_ mask: NSEvent.EventTypeMask, _ handler: @escaping () -> Void) {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { _ in handler() }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { e in handler(); return e }) { monitors.append(m) }
    }

    private func down() {
        reset()
        let mouse = NSEvent.mouseLocation
        let p = Geometry.flip(mouse, primaryHeight: primaryHeight)
        guard !config.zones.isEmpty,
              let el = WindowAX.window(at: p), WindowAX.inTitleBar(p, of: el),
              let id = WindowAX.windowID(of: el) else { return }
        target = (el, id)
        downPoint = mouse
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        guard let t = target else { return }
        let flags = NSEvent.modifierFlags
        let mouse = NSEvent.mouseLocation
        guard flags.contains(.shift),
              hypot(mouse.x - downPoint.x, mouse.y - downPoint.y) > 4,
              let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) else {
            hideOverlay()
            return
        }
        if overlay?.screen.frame != screen.frame {  // frame, not identity: NSScreen instances can be replaced
            overlay?.hide()
            overlay = ZoneOverlay(screen: screen)
            swept = []
        }
        let area = usableArea(for: screen)
        let hit = Geometry.zoneIndex(at: Geometry.flip(mouse, primaryHeight: primaryHeight), zones: config.zones, in: area)
        if flags.contains(.control) {
            if let hit, !swept.contains(hit) { swept.append(hit) }
        } else {
            swept = hit.map { [$0] } ?? []
        }
        overlay?.update(zoneRects: config.zones.map { displayRect($0, in: area) }, highlighted: Set(swept))
        overlay?.show(below: t.id)
    }

    private func up() {
        defer { reset() }
        guard let t = target, let overlay, !swept.isEmpty else { return }
        let zones = swept.compactMap { config.zones.indices.contains($0) ? config.zones[$0] : nil }
        let area = usableArea(for: overlay.screen)
        guard let f = Geometry.frame(for: zones, in: area, gap: config.gap) else { return }
        if config.animate { WindowAX.animate(to: f, of: t.el) } else { WindowAX.setFrame(f, of: t.el) }
    }

    private func hideOverlay() { overlay?.hide(); overlay = nil; swept = [] }

    private func reset() {
        timer?.invalidate(); timer = nil
        hideOverlay()
        target = nil
    }

    private func usableArea(for screen: NSScreen) -> CGRect {
        Geometry.usableArea(visible: Geometry.flip(screen.visibleFrame, primaryHeight: primaryHeight),
                            inset: config.stageManagerInset, on: config.stageManagerOn)
    }

    /// Zone as it will land (gap applied), in AppKit global coordinates for drawing.
    private func displayRect(_ z: Zone, in area: CGRect) -> CGRect {
        Geometry.flip(Geometry.frame(for: [z], in: area, gap: config.gap)!, primaryHeight: primaryHeight)
    }
}
