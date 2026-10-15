import AppKit
import FancyZonesCore

private final class EditorWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

final class ZoneEditor {
    private var window: EditorWindow?

    /// `onSave` receives the edited zones plus the gap / Stage Manager settings, all edited in the same screen.
    func open(config: Config, screen: NSScreen,
              onSave: @escaping (_ zones: [Zone], _ gap: Double, _ inset: Double, _ stageManagerOn: Bool, _ animate: Bool) -> Void) {
        window?.close()
        let primaryH = NSScreen.screens[0].frame.height
        let screenAX = Geometry.flip(screen.frame, primaryHeight: primaryH)
        // View is flipped (top-left origin), so AX offsets relative to the screen's top-left map directly.
        let visible = Geometry.flip(screen.visibleFrame, primaryHeight: primaryH)
            .offsetBy(dx: -screenAX.minX, dy: -screenAX.minY)

        let w = EditorWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.level = .screenSaver
        w.isOpaque = false
        w.backgroundColor = .clear
        w.isReleasedWhenClosed = false

        let view = EditorView(frame: NSRect(origin: .zero, size: screen.frame.size), visible: visible,
                              gap: config.gap, inset: config.stageManagerInset, stageManagerOn: config.stageManagerOn,
                              animate: config.animate, zones: config.zones)
        view.onDone = { [weak self, weak view] save in
            if save, let view { onSave(view.zones, view.gap, view.inset, view.stageManagerOn, view.animate) }
            self?.window?.close()
            self?.window = nil
        }
        w.contentView = view
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        w.makeFirstResponder(view)
    }
}

private final class EditorView: NSView, NSTextFieldDelegate {
    let visible: CGRect
    private(set) var gap: Double
    private(set) var inset: Double
    private(set) var stageManagerOn: Bool
    private(set) var animate: Bool
    var zones: [Zone]
    var onDone: (Bool) -> Void = { _ in }

    private var start: (col: Int, row: Int)?
    private var current: (col: Int, row: Int)?
    private let gapField = NSTextField(string: "")
    private let insetField = NSTextField(string: "")
    private let toggle = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let animateToggle = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let panel = NSStackView()

    /// Grid area: visible frame (menu bar + Dock excluded) minus the Stage Manager inset when on.
    private var area: CGRect { Geometry.usableArea(visible: visible, inset: inset, on: stageManagerOn) }

    init(frame: NSRect, visible: CGRect, gap: Double, inset: Double, stageManagerOn: Bool, animate: Bool, zones: [Zone]) {
        self.visible = visible
        self.gap = gap
        self.inset = inset
        self.stageManagerOn = stageManagerOn
        self.animate = animate
        self.zones = zones
        super.init(frame: frame)
        buildPanel()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    // MARK: controls

    private func label(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.textColor = .white
        return l
    }

    private func buildPanel() {
        for f in [gapField, insetField] {
            f.delegate = self
            f.widthAnchor.constraint(equalToConstant: 64).isActive = true
        }
        gapField.doubleValue = gap
        insetField.doubleValue = inset
        toggle.attributedTitle = NSAttributedString(string: "Stage Manager inset (px)",
                                                    attributes: [.foregroundColor: NSColor.white])
        toggle.state = stageManagerOn ? .on : .off
        toggle.target = self
        toggle.action = #selector(fieldsChanged)
        animateToggle.attributedTitle = NSAttributedString(string: "Animate", attributes: [.foregroundColor: NSColor.white])
        animateToggle.state = animate ? .on : .off
        animateToggle.target = self
        animateToggle.action = #selector(fieldsChanged)

        let row = NSStackView(views: [label("Gap (px)"), gapField, toggle, insetField, animateToggle])
        row.spacing = 8
        let hint = label("Drag: add zone  ·  Click zone: delete  ·  Return: save  ·  Esc: cancel  ·  Amber = gap")
        panel.setViews([hint, row], in: .top)
        panel.orientation = .vertical
        panel.alignment = .centerX
        panel.spacing = 8
        panel.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        let size = panel.fittingSize
        panel.frame = NSRect(x: (bounds.width - size.width) / 2, y: visible.minY + 16, width: size.width, height: size.height)
        panel.wantsLayer = true
        panel.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        panel.layer?.cornerRadius = 10
        addSubview(panel)
    }

    @objc private func fieldsChanged() {
        gap = max(0, gapField.doubleValue)
        inset = max(0, insetField.doubleValue)
        stageManagerOn = toggle.state == .on
        animate = animateToggle.state == .on
        needsDisplay = true
    }

    func controlTextDidChange(_ obj: Notification) { fieldsChanged() }

    /// Esc cancels the editor even while a field has focus; Return commits the field and returns focus to the grid.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.cancelOperation(_:)) { onDone(false); return true }
        if sel == #selector(NSResponder.insertNewline(_:)) { fieldsChanged(); window?.makeFirstResponder(self); return true }
        return false
    }

    // MARK: drawing

    override func draw(_ dirty: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()
        let area = self.area

        if stageManagerOn, area.minX > visible.minX { drawStageManagerBand(CGRect(x: visible.minX, y: visible.minY,
                                                                                   width: area.minX - visible.minX, height: visible.height)) }

        let grid = NSBezierPath()
        for i in 0...Zone.grid {
            let t = CGFloat(i) / CGFloat(Zone.grid)
            let x = area.minX + area.width * t, y = area.minY + area.height * t
            grid.move(to: CGPoint(x: x, y: area.minY)); grid.line(to: CGPoint(x: x, y: area.maxY))
            grid.move(to: CGPoint(x: area.minX, y: y)); grid.line(to: CGPoint(x: area.maxX, y: y))
        }
        NSColor.white.withAlphaComponent(0.25).setStroke()
        grid.lineWidth = 1
        grid.stroke()

        // Amber = the full grid cell; the zone frame on top leaves the gap showing as an amber band.
        for z in zones {
            NSColor.systemOrange.withAlphaComponent(0.45).setFill()
            Geometry.cellRect(z, in: area).fill()
            fill(z, NSColor.controlAccentColor.withAlphaComponent(0.85))
        }
        if let s = start, let c = current {
            let p = Zone.spanning(s, c)
            fill(p, zones.canAdd(p) ? NSColor.white.withAlphaComponent(0.35) : NSColor.systemRed.withAlphaComponent(0.5))
        }
    }

    private func drawStageManagerBand(_ band: CGRect) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: band).addClip()
        NSColor.systemPurple.withAlphaComponent(0.3).setFill()
        band.fill()
        let hatch = NSBezierPath()
        var x = band.minX - band.height
        while x < band.maxX {
            hatch.move(to: CGPoint(x: x, y: band.maxY)); hatch.line(to: CGPoint(x: x + band.height, y: band.minY))
            x += 12
        }
        NSColor.systemPurple.withAlphaComponent(0.55).setStroke()
        hatch.lineWidth = 1
        hatch.stroke()
        NSGraphicsContext.restoreGraphicsState()

        let style = NSMutableParagraphStyle()
        style.alignment = .center
        ("Stage Manager\n\(Int(inset)) px" as NSString).draw(
            in: band.insetBy(dx: 4, dy: 80).offsetBy(dx: 0, dy: 60),
            withAttributes: [.foregroundColor: NSColor.white, .paragraphStyle: style,
                             .font: NSFont.systemFont(ofSize: 12, weight: .semibold)])
    }

    private func fill(_ z: Zone, _ color: NSColor) {
        guard let f = Geometry.frame(for: [z], in: area, gap: gap) else { return }
        color.setFill()
        NSBezierPath(roundedRect: f, xRadius: 6, yRadius: 6).fill()
    }

    // MARK: mouse / keys

    private func cell(_ e: NSEvent) -> (col: Int, row: Int)? {
        let p = convert(e.locationInWindow, from: nil)
        if panel.frame.contains(p) { return nil }  // clicks on the control panel never touch the grid
        return Geometry.cell(at: p, in: area)
    }

    override func mouseDown(with e: NSEvent) {
        window?.makeFirstResponder(self)  // ends any field editing
        start = cell(e); current = start; needsDisplay = true
    }

    override func mouseDragged(with e: NSEvent) {
        if let c = cell(e) { current = c }
        needsDisplay = true
    }

    override func mouseUp(with e: NSEvent) {
        defer { start = nil; current = nil; needsDisplay = true }
        guard let s = start, let c = current else { return }
        if s == c, let i = zones.firstIndex(where: { $0.contains(col: s.col, row: s.row) }) {
            zones.remove(at: i)  // plain click on an existing zone deletes it
            return
        }
        let z = Zone.spanning(s, c)
        if zones.canAdd(z) { zones.append(z) } else { NSSound.beep() }
    }

    override func keyDown(with e: NSEvent) {
        switch e.keyCode {
        case 53: onDone(false)       // Esc
        case 36, 76: onDone(true)    // Return / keypad Enter
        default: super.keyDown(with: e)
        }
    }
}
