import AppKit
import ApplicationServices
import FancyZonesCore

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ el: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Accessibility helpers. All points/rects are in AX (top-left origin) coordinates.
enum WindowAX {
    /// Height of the strip at the top of a window that counts as "title bar". Tune if custom title bars misbehave.
    static let titleBarHeight: CGFloat = 40

    private static func attr<T>(_ el: AXUIElement, _ name: String) -> T? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success else { return nil }
        return v as? T
    }

    static func window(at p: CGPoint) -> AXUIElement? {
        var el: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(p.x), Float(p.y), &el) == .success,
              var cur = el else { return nil }
        while (attr(cur, kAXRoleAttribute) as String?) != kAXWindowRole {
            guard let parent: AXUIElement = attr(cur, kAXParentAttribute) else { return nil }
            cur = parent
        }
        return cur
    }

    static func frame(of w: AXUIElement) -> CGRect? {
        guard let pv: AXValue = attr(w, kAXPositionAttribute), let sv: AXValue = attr(w, kAXSizeAttribute) else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        guard AXValueGetValue(pv, .cgPoint, &p), AXValueGetValue(sv, .cgSize, &s) else { return nil }
        return CGRect(origin: p, size: s)
    }

    static func inTitleBar(_ p: CGPoint, of w: AXUIElement) -> Bool {
        guard let f = frame(of: w) else { return false }
        return p.x >= f.minX && p.x <= f.maxX && p.y >= f.minY && p.y <= f.minY + titleBarHeight
    }

    static func windowID(of w: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(w, &id) == .success ? id : nil
    }

    /// Size, position, size again: moving across displays can make the first size get clamped.
    /// Errors are ignored on purpose; apps that refuse resizes just land as close as they allow.
    /// `thorough: false` skips the trailing size set (2 IPC calls instead of 3) for animation ticks.
    static func setFrame(_ r: CGRect, of w: AXUIElement, thorough: Bool = true) {
        var size = r.size, origin = r.origin
        guard let sv = AXValueCreate(.cgSize, &size), let pv = AXValueCreate(.cgPoint, &origin) else { return }
        AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, sv)
        AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, pv)
        if thorough { AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, sv) }
    }

    private static var tween: Timer?

    /// Eases the window to `target` over `duration`, then applies the exact final frame.
    /// ponytail: one AX round-trip per tick on the main thread; heavy apps may look steppy. Fallback: outline-only ghost.
    static func animate(to target: CGRect, of w: AXUIElement, duration: TimeInterval = 0.15) {
        tween?.invalidate()
        guard let from = frame(of: w) else { setFrame(target, of: w); return }
        let t0 = ProcessInfo.processInfo.systemUptime
        tween = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { timer in
            let p = (ProcessInfo.processInfo.systemUptime - t0) / duration
            if p >= 1 {
                timer.invalidate()
                setFrame(target, of: w)
                return
            }
            setFrame(Geometry.lerp(from: from, to: target, t: Geometry.easeOut(p)), of: w, thorough: false)
        }
    }
}
