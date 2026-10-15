import AppKit
import FancyZonesCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private var config = Config.load() {
        didSet {
            try? config.save()  // ponytail: silent save failure; surface in UI if it ever matters
            drag.config = config
        }
    }
    private lazy var drag = DragSnap(config: config)
    private let editor = ZoneEditor()

    func applicationDidFinishLaunching(_ n: Notification) {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary)

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.split.3x3", accessibilityDescription: "mac-fancy-zones")

        let menu = NSMenu()
        for (title, action) in [("Edit Zones…", #selector(editZones)),
                                ("Accessibility Settings…", #selector(openAccessibility))] {
            let mi = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            mi.target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        drag.start()
    }

    @objc private func editZones() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.screens[0]
        editor.open(config: config, screen: screen) { [weak self] zones, gap, inset, on, animate in
            guard let self else { return }
            var c = self.config.with(gap: gap, stageManagerInset: inset, stageManagerOn: on, animate: animate)
            c.zones = zones
            self.config = c
        }
    }

    @objc private func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
