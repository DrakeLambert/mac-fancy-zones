# mac-fancy-zones Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Menu-bar-only native Swift app that snaps windows into user-drawn zones on a 12×12 grid via Shift (single zone) / Shift+Ctrl (multi-zone) title-bar drags.

**Architecture:** SwiftPM package with a pure library `FancyZonesCore` (zones, config JSON, geometry — all unit-checked), an AppKit executable `MacFancyZones` (status item, settings, zone editor, drag-to-snap using global `NSEvent` mouse monitors + Accessibility API), and an assert-based `CoreChecks` executable that exercises the core. Overlay windows stay at normal window level and are ordered directly below the dragged window. A throwaway `Probe` executable de-risks that ordering first.

**Tech Stack:** Swift 6.3 toolchain (Swift 5 language mode, `swift-tools-version:5.9`), AppKit, ApplicationServices (AX), Foundation. macOS 13+. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-10-15-mac-fancy-zones-design.md`

## Global Constraints

- Only the Command Line Tools are installed (no Xcode). **XCTest and Swift Testing are unavailable.** Core logic is tested via the `CoreChecks` executable: `swift run CoreChecks` must print `all checks passed` and exit 0.
- Native Swift, no third-party dependencies, menu-bar-only app (`LSUIElement` / `.accessory` activation policy).
- Grid is 12×12 (`Zone.grid == 12`); one single layout applies to all displays; zones never overlap.
- Config path: `~/Library/Application Support/mac-fancy-zones/config.json`; defaults: gap 5, stageManagerInset 100, stageManagerOn false, no zones.
- Gap rule: neighbors end up `gap` px apart (`gap/2` per interior side); sides on the usable-area edge get the full `gap`.
- Usable area = `screen.visibleFrame` (menu bar + Dock excluded) minus left Stage Manager inset when toggle is on.
- Drag monitors are listen-only `NSEvent` global monitors; **no `CGEventTap`**.
- Overlay windows are click-through, `.normal` level, ordered `.below` the dragged window's `CGWindowID`.
- Geometry in `FancyZonesCore` uses **top-left-origin (AX) coordinates**; AppKit (bottom-left) values are converted with `Geometry.flip`.
- Out of scope: multiple/per-display layouts, hotkey snapping, animations, launch-at-login, Stage Manager auto-detect, edge-drag zone resize.
- Commit messages end with the line `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.

## Review Focus

- **Corrupt or partial `config.json`:** unparsable file → defaults, original preserved as `config.json.corrupt` (no data loss); partial file (`{"gap": 8}`) → missing keys default. (Task 3)
- **Overlapping / out-of-grid / zero-size zones in the config file:** first valid zone wins, others dropped; negative gap clamped to 0. (Task 3)
- **No zones defined:** Shift-drag shows nothing, never moves the window (`frame(for: [])` and `zoneIndex` return nil). (Tasks 4, 7)
- **Absurd gap or Stage Manager inset** (bigger than a cell / the screen): sizes clamp to ≥ 1, never negative. (Task 4)
- **Secondary displays with negative or above-primary origins:** `flip` and geometry work with negative x/y. (Task 4)

---

### Task 1: Spike — can we order our overlay below another app's window?

This is a **throwaway probe** (deleted in Task 8). Spec risk #1. Requires a human at the screen.

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `Sources/Probe/main.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: a go/no-go answer. `Package.swift` skeleton that later tasks extend.

- [ ] **Step 1: Create `.gitignore`**

```
.build/
build/
.swiftpm/
.DS_Store
.claude/worktrees/
```

- [ ] **Step 2: Create `Package.swift`**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "mac-fancy-zones",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Probe"),
    ]
)
```

- [ ] **Step 3: Create `Sources/Probe/main.swift`**

```swift
// THROWAWAY spike: tints the screen red *below* whichever window you press the mouse on.
import AppKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ el: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

_ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let screen = NSScreen.main!
let overlay = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
overlay.isOpaque = false
overlay.backgroundColor = NSColor.systemRed.withAlphaComponent(0.4)
overlay.ignoresMouseEvents = true
overlay.level = .normal
overlay.collectionBehavior = [.canJoinAllSpaces, .stationary]
overlay.isReleasedWhenClosed = false

func windowID(at p: CGPoint) -> CGWindowID? {
    var el: AXUIElement?
    guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(p.x), Float(p.y), &el) == .success,
          var cur = el else { return nil }
    while true {
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(cur, kAXRoleAttribute as CFString, &role)
        if (role as? String) == kAXWindowRole { break }
        var parent: CFTypeRef?
        guard AXUIElementCopyAttributeValue(cur, kAXParentAttribute as CFString, &parent) == .success,
              let par = parent else { return nil }
        cur = par as! AXUIElement
    }
    var id: CGWindowID = 0
    return _AXUIElementGetWindow(cur, &id) == .success ? id : nil
}

var timer: Timer?

NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { _ in
    let m = NSEvent.mouseLocation
    let p = CGPoint(x: m.x, y: NSScreen.screens[0].frame.height - m.y)
    guard let id = windowID(at: p) else { print("no window under cursor (Accessibility granted?)"); return }
    print("dragging window id \(id)")
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { _ in
        overlay.order(.below, relativeTo: Int(id))
    }
}
NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
    timer?.invalidate(); timer = nil
    overlay.orderOut(nil)
}

print("Probe running. Ctrl-C to quit.")
app.run()
```

- [ ] **Step 4: Build**

Run: `swift build --product Probe`
Expected: `Build complete!`

- [ ] **Step 5: Manual verification (human required — stop here and ask the user)**

Run: `swift run Probe`, grant Accessibility to the terminal app if prompted (System Settings → Privacy & Security → Accessibility), then re-run. Open two or more Finder windows (and a Terminal) side by side. Press and hold the mouse on a Finder window's title bar and drag it around.

- **PASS:** while the mouse is held, everything on screen is tinted red **except the dragged window**, which stays fully un-tinted and on top; other windows are tinted. On release the tint disappears.
- **FAIL:** the dragged window is tinted too, or no tint appears at all.

If **FAIL: stop the whole plan** and report to the user. The fallback (outline-only floating overlay that draws over the dragged window) needs their sign-off. Do not proceed to Task 2.

- [ ] **Step 6: Commit**

```bash
git add .gitignore Package.swift Sources/Probe
git commit -m "spike: probe cross-app overlay ordering

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Check harness + `Zone`

**Files:**
- Modify: `Package.swift` (replace whole file)
- Create: `Sources/CoreChecks/Check.swift`
- Create: `Sources/CoreChecks/ZoneChecks.swift`
- Create: `Sources/CoreChecks/main.swift`
- Create: `Sources/FancyZonesCore/Zone.swift`

**Interfaces:**
- Consumes: nothing.
- Produces (`FancyZonesCore`, all `public`):
  - `struct Zone: Codable, Equatable { col, row, w, h: Int; init(col:row:w:h:); static let grid = 12; var isValid: Bool; func overlaps(_: Zone) -> Bool; func contains(col: Int, row: Int) -> Bool; static func spanning(_ a: (col: Int, row: Int), _ b: (col: Int, row: Int)) -> Zone; static func bounds(of: [Zone]) -> Zone? }`
  - `extension Array where Element == Zone { func canAdd(_ z: Zone) -> Bool; func sanitized() -> [Zone] }`
- Produces (`CoreChecks`, internal): `check(_ cond: @autoclosure () -> Bool, _ msg: String, line: Int = #line)`, `near(_:_:) -> Bool`, `nearRect(_:_:) -> Bool`, global `failures: Int`.

- [ ] **Step 1: Replace `Package.swift`**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "mac-fancy-zones",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "FancyZonesCore"),
        .executableTarget(name: "CoreChecks", dependencies: ["FancyZonesCore"]),
        .executableTarget(name: "Probe"),
    ]
)
```

- [ ] **Step 2: Write the failing checks**

`Sources/CoreChecks/Check.swift`:

```swift
import Foundation

var failures = 0

func check(_ cond: @autoclosure () -> Bool, _ msg: String, line: Int = #line) {
    if !cond() { failures += 1; print("FAIL (line \(line)): \(msg)") }
}

func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.001 }

func nearRect(_ a: CGRect, _ b: CGRect) -> Bool {
    near(a.minX, b.minX) && near(a.minY, b.minY) && near(a.width, b.width) && near(a.height, b.height)
}
```

`Sources/CoreChecks/ZoneChecks.swift`:

```swift
import FancyZonesCore

func zoneChecks() {
    let a = Zone(col: 0, row: 0, w: 6, h: 12)
    let b = Zone(col: 6, row: 0, w: 6, h: 6)

    check(a.isValid, "left half is valid")
    check(!Zone(col: 8, row: 0, w: 6, h: 1).isValid, "past right edge is invalid")
    check(!Zone(col: 0, row: 11, w: 1, h: 2).isValid, "past bottom edge is invalid")
    check(!Zone(col: 0, row: 0, w: 0, h: 1).isValid, "zero width is invalid")
    check(!Zone(col: -1, row: 0, w: 1, h: 1).isValid, "negative col is invalid")

    check(!a.overlaps(Zone(col: 6, row: 0, w: 6, h: 12)), "adjacent zones do not overlap")
    check(a.overlaps(Zone(col: 5, row: 3, w: 2, h: 2)), "intersecting zones overlap")

    check(a.contains(col: 5, row: 11), "contains last cell")
    check(!a.contains(col: 6, row: 0), "does not contain neighbor cell")

    check(Zone.spanning((col: 3, row: 4), (col: 1, row: 2)) == Zone(col: 1, row: 2, w: 3, h: 3),
          "spanning is corner-order independent")
    check(Zone.spanning((col: 2, row: 2), (col: 2, row: 2)) == Zone(col: 2, row: 2, w: 1, h: 1),
          "spanning one cell is 1x1")

    check(Zone.bounds(of: [a, b]) == Zone(col: 0, row: 0, w: 12, h: 12), "bounds covers all zones")
    check(Zone.bounds(of: []) == nil, "bounds of nothing is nil")

    check([a].canAdd(b), "can add non-overlapping zone")
    check(![a].canAdd(Zone(col: 5, row: 0, w: 2, h: 2)), "cannot add overlapping zone")
    check(![a].canAdd(Zone(col: 0, row: 0, w: 0, h: 0)), "cannot add invalid zone")

    let dirty = [a, Zone(col: 5, row: 0, w: 2, h: 2), b, Zone(col: 0, row: 0, w: 0, h: 0)]
    check(dirty.sanitized() == [a, b], "sanitized keeps first, drops overlapping and invalid")
}
```

`Sources/CoreChecks/main.swift`:

```swift
import Foundation

zoneChecks()

if failures > 0 { print("\(failures) check(s) failed"); exit(1) }
print("all checks passed")
```

- [ ] **Step 3: Run to verify it fails**

Run: `swift run CoreChecks`
Expected: build FAILS (target `FancyZonesCore` has no sources / cannot find `Zone`).

- [ ] **Step 4: Implement `Sources/FancyZonesCore/Zone.swift`**

```swift
/// A rectangle of grid cells. `row` 0 is the top row.
public struct Zone: Codable, Equatable {
    public static let grid = 12

    public var col: Int
    public var row: Int
    public var w: Int
    public var h: Int

    public init(col: Int, row: Int, w: Int, h: Int) {
        self.col = col; self.row = row; self.w = w; self.h = h
    }

    public var isValid: Bool {
        w >= 1 && h >= 1 && col >= 0 && row >= 0 && col + w <= Zone.grid && row + h <= Zone.grid
    }

    public func overlaps(_ o: Zone) -> Bool {
        col < o.col + o.w && o.col < col + w && row < o.row + o.h && o.row < row + h
    }

    public func contains(col c: Int, row r: Int) -> Bool {
        c >= col && c < col + w && r >= row && r < row + h
    }

    /// Zone covering the cells between two corner cells, inclusive, in any order.
    public static func spanning(_ a: (col: Int, row: Int), _ b: (col: Int, row: Int)) -> Zone {
        Zone(col: min(a.col, b.col), row: min(a.row, b.row),
             w: abs(a.col - b.col) + 1, h: abs(a.row - b.row) + 1)
    }

    /// Smallest zone containing all of `zones`.
    public static func bounds(of zones: [Zone]) -> Zone? {
        guard let f = zones.first else { return nil }
        var c0 = f.col, r0 = f.row, c1 = f.col + f.w, r1 = f.row + f.h
        for z in zones.dropFirst() {
            c0 = min(c0, z.col); r0 = min(r0, z.row)
            c1 = max(c1, z.col + z.w); r1 = max(r1, z.row + z.h)
        }
        return Zone(col: c0, row: r0, w: c1 - c0, h: r1 - r0)
    }
}

public extension Array where Element == Zone {
    func canAdd(_ z: Zone) -> Bool { z.isValid && !contains { $0.overlaps(z) } }

    /// Drops invalid zones and any zone overlapping an earlier kept zone.
    func sanitized() -> [Zone] {
        reduce(into: [Zone]()) { acc, z in if acc.canAdd(z) { acc.append(z) } }
    }
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `swift run CoreChecks`
Expected: `all checks passed`

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/CoreChecks Sources/FancyZonesCore
git commit -m "feat: Zone model and CoreChecks harness

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `Config` load/save

**Files:**
- Create: `Sources/FancyZonesCore/Config.swift`
- Create: `Sources/CoreChecks/ConfigChecks.swift`
- Modify: `Sources/CoreChecks/main.swift`

**Interfaces:**
- Consumes: `Zone`, `[Zone].sanitized()`.
- Produces: `public struct Config: Codable, Equatable { var gap: Double; var stageManagerInset: Double; var stageManagerOn: Bool; var zones: [Zone]; init(); static var defaultURL: URL; static func load(from: URL = defaultURL) -> Config; func save(to: URL = Config.defaultURL) throws }`. `load` never throws: missing → defaults; undecodable → defaults and the bad file is renamed to `<name>.corrupt`; success → `gap`/`inset` clamped ≥ 0, zones sanitized.

- [ ] **Step 1: Write the failing checks** — `Sources/CoreChecks/ConfigChecks.swift`:

```swift
import Foundation
import FancyZonesCore

func configChecks() {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mfz-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("config.json")

    check(Config.load(from: url) == Config(), "missing file -> defaults")
    let d = Config()
    check(d.gap == 5 && d.stageManagerInset == 100 && !d.stageManagerOn && d.zones.isEmpty, "default values")

    var c = Config()
    c.gap = 8
    c.stageManagerOn = true
    c.zones = [Zone(col: 0, row: 0, w: 4, h: 12)]
    try! c.save(to: url)  // also creates the directory
    check(Config.load(from: url) == c, "save/load round trip")

    try! Data(#"{"gap": 8}"#.utf8).write(to: url)
    var partial = Config()
    partial.gap = 8
    check(Config.load(from: url) == partial, "partial file fills missing keys with defaults")

    let messy = #"{"gap":-3,"zones":[{"col":0,"row":0,"w":6,"h":12},{"col":5,"row":0,"w":2,"h":2},{"col":0,"row":0,"w":99,"h":1}]}"#
    try! Data(messy.utf8).write(to: url)
    let s = Config.load(from: url)
    check(s.zones == [Zone(col: 0, row: 0, w: 6, h: 12)], "overlapping and out-of-grid zones dropped")
    check(s.gap == 0, "negative gap clamped to 0")

    try! Data("not json {".utf8).write(to: url)
    check(Config.load(from: url) == Config(), "corrupt file -> defaults")
    check(!FileManager.default.fileExists(atPath: url.path), "corrupt file moved aside")
    check(FileManager.default.contents(atPath: url.path + ".corrupt") == Data("not json {".utf8),
          "corrupt content preserved")
}
```

- [ ] **Step 2: Wire into `main.swift`** — replace the file with:

```swift
import Foundation

zoneChecks()
configChecks()

if failures > 0 { print("\(failures) check(s) failed"); exit(1) }
print("all checks passed")
```

- [ ] **Step 3: Run to verify it fails**

Run: `swift run CoreChecks`
Expected: build FAILS — `cannot find 'Config' in scope`.

- [ ] **Step 4: Implement `Sources/FancyZonesCore/Config.swift`**

```swift
import Foundation

public struct Config: Codable, Equatable {
    public var gap: Double = 5
    public var stageManagerInset: Double = 100
    public var stageManagerOn: Bool = false
    public var zones: [Zone] = []

    public init() {}

    enum CodingKeys: String, CodingKey { case gap, stageManagerInset, stageManagerOn, zones }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gap = try c.decodeIfPresent(Double.self, forKey: .gap) ?? gap
        stageManagerInset = try c.decodeIfPresent(Double.self, forKey: .stageManagerInset) ?? stageManagerInset
        stageManagerOn = try c.decodeIfPresent(Bool.self, forKey: .stageManagerOn) ?? stageManagerOn
        zones = try c.decodeIfPresent([Zone].self, forKey: .zones) ?? zones
    }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mac-fancy-zones/config.json")
    }

    public static func load(from url: URL = defaultURL) -> Config {
        guard let data = try? Data(contentsOf: url) else { return Config() }
        guard var c = try? JSONDecoder().decode(Config.self, from: data) else {
            let aside = URL(fileURLWithPath: url.path + ".corrupt")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: url, to: aside)  // keep user's data; next save won't clobber it
            return Config()
        }
        c.gap = max(0, c.gap)
        c.stageManagerInset = max(0, c.stageManagerInset)
        c.zones = c.zones.sanitized()
        return c
    }

    public func save(to url: URL = Config.defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: url, options: .atomic)
    }
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `swift run CoreChecks`
Expected: `all checks passed`

- [ ] **Step 6: Commit**

```bash
git add Sources/FancyZonesCore/Config.swift Sources/CoreChecks
git commit -m "feat: Config JSON load/save with corrupt-file preservation

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `Geometry`

**Files:**
- Create: `Sources/FancyZonesCore/Geometry.swift`
- Create: `Sources/CoreChecks/GeometryChecks.swift`
- Modify: `Sources/CoreChecks/main.swift`

**Interfaces:**
- Consumes: `Zone`, `Zone.bounds(of:)`, `Zone.grid`.
- Produces (`public enum Geometry`; all rects in top-left-origin coordinates except where noted):
  - `static func flip(_ r: CGRect, primaryHeight: CGFloat) -> CGRect` — converts AppKit↔AX, self-inverse
  - `static func flip(_ p: CGPoint, primaryHeight: CGFloat) -> CGPoint`
  - `static func usableArea(visible: CGRect, inset: Double, on: Bool) -> CGRect`
  - `static func cellRect(_ z: Zone, in area: CGRect) -> CGRect` — no gap
  - `static func frame(for zones: [Zone], in area: CGRect, gap: Double) -> CGRect?` — bounding box of zones with gap applied; nil for empty
  - `static func zoneIndex(at p: CGPoint, zones: [Zone], in area: CGRect) -> Int?`
  - `static func cell(at p: CGPoint, in area: CGRect) -> (col: Int, row: Int)?`

- [ ] **Step 1: Write the failing checks** — `Sources/CoreChecks/GeometryChecks.swift`:

```swift
import CoreGraphics
import FancyZonesCore

func geometryChecks() {
    let area = CGRect(x: 0, y: 0, width: 1200, height: 1200)
    let left = Zone(col: 0, row: 0, w: 6, h: 12)
    let right = Zone(col: 6, row: 0, w: 6, h: 12)

    // gap: shared between neighbors, full gap at edges
    let fl = Geometry.frame(for: [left], in: area, gap: 10)!
    let fr = Geometry.frame(for: [right], in: area, gap: 10)!
    check(nearRect(fl, CGRect(x: 10, y: 10, width: 585, height: 1180)), "left zone frame")
    check(nearRect(fr, CGRect(x: 605, y: 10, width: 585, height: 1180)), "right zone frame")
    check(near(fr.minX - fl.maxX, 10), "horizontal neighbors are exactly gap apart")
    check(near(fl.minX, 10) && near(area.maxX - fr.maxX, 10), "edge distance equals gap")

    let tl = Geometry.frame(for: [Zone(col: 0, row: 0, w: 6, h: 6)], in: area, gap: 10)!
    let bl = Geometry.frame(for: [Zone(col: 0, row: 6, w: 6, h: 6)], in: area, gap: 10)!
    check(near(bl.minY - tl.maxY, 10), "vertical neighbors are exactly gap apart")

    // multi-zone span fills the union
    check(nearRect(Geometry.frame(for: [left, right], in: area, gap: 10)!,
                   CGRect(x: 10, y: 10, width: 1180, height: 1180)), "span of both halves")

    // no zones
    check(Geometry.frame(for: [], in: area, gap: 10) == nil, "frame of no zones is nil")
    check(Geometry.zoneIndex(at: CGPoint(x: 300, y: 300), zones: [], in: area) == nil, "no zones -> no hit")

    // hit testing uses gap-free cells (no dead strips); max edge exclusive
    check(Geometry.zoneIndex(at: CGPoint(x: 300, y: 300), zones: [left, right], in: area) == 0, "hit left")
    check(Geometry.zoneIndex(at: CGPoint(x: 900, y: 300), zones: [left, right], in: area) == 1, "hit right")
    check(Geometry.zoneIndex(at: CGPoint(x: 600, y: 300), zones: [left, right], in: area) == 1, "boundary belongs to right")
    check(Geometry.zoneIndex(at: CGPoint(x: 1200, y: 5), zones: [left, right], in: area) == nil, "outside area")

    // absurd gap never yields negative size
    let tiny = Geometry.frame(for: [left], in: area, gap: 5000)!
    check(tiny.width >= 1 && tiny.height >= 1, "huge gap clamps size to >= 1")

    // usable area: menu bar already excluded by visibleFrame; Stage Manager inset on the left
    let vis = CGRect(x: 0, y: 25, width: 1000, height: 775)
    check(nearRect(Geometry.usableArea(visible: vis, inset: 100, on: true), CGRect(x: 100, y: 25, width: 900, height: 775)),
          "inset on")
    check(Geometry.usableArea(visible: vis, inset: 100, on: false) == vis, "inset off")
    check(Geometry.usableArea(visible: vis, inset: 5000, on: true).width >= 1, "huge inset keeps width >= 1")

    // frames honor a non-zero area origin
    let off = CGRect(x: 100, y: 25, width: 900, height: 775)
    check(nearRect(Geometry.frame(for: [Zone(col: 0, row: 0, w: 12, h: 12)], in: off, gap: 5)!,
                   CGRect(x: 105, y: 30, width: 890, height: 765)), "offset area + gap")

    // cell lookup (editor)
    check(Geometry.cell(at: CGPoint(x: 0, y: 0), in: area).map { $0 == (0, 0) } == true, "cell origin")
    check(Geometry.cell(at: CGPoint(x: 1199, y: 1199), in: area).map { $0 == (11, 11) } == true, "cell last")
    check(Geometry.cell(at: CGPoint(x: 600, y: 0), in: area).map { $0 == (6, 0) } == true, "cell middle")
    check(Geometry.cell(at: CGPoint(x: -1, y: 5), in: area) == nil, "cell left of area")
    check(Geometry.cell(at: CGPoint(x: 1200, y: 5), in: area) == nil, "cell right of area")

    // flip: AppKit (bottom-left) <-> AX (top-left), including secondary displays at negative origins
    check(nearRect(Geometry.flip(CGRect(x: 0, y: 0, width: 100, height: 50), primaryHeight: 1000),
                   CGRect(x: 0, y: 950, width: 100, height: 50)), "flip primary")
    check(nearRect(Geometry.flip(CGRect(x: 0, y: 1000, width: 800, height: 600), primaryHeight: 1000),
                   CGRect(x: 0, y: -600, width: 800, height: 600)), "flip display above primary -> negative y")
    check(nearRect(Geometry.flip(CGRect(x: -1920, y: 0, width: 1920, height: 1080), primaryHeight: 1000),
                   CGRect(x: -1920, y: -80, width: 1920, height: 1080)), "flip display left of primary -> negative x")
    let r = CGRect(x: -300, y: 40, width: 70, height: 90)
    check(nearRect(Geometry.flip(Geometry.flip(r, primaryHeight: 777), primaryHeight: 777), r), "flip is self-inverse")
    let p = Geometry.flip(CGPoint(x: 10, y: 10), primaryHeight: 1000)
    check(near(p.x, 10) && near(p.y, 990), "flip point")
}
```

- [ ] **Step 2: Wire into `main.swift`** — add `geometryChecks()` after `configChecks()`:

```swift
import Foundation

zoneChecks()
configChecks()
geometryChecks()

if failures > 0 { print("\(failures) check(s) failed"); exit(1) }
print("all checks passed")
```

- [ ] **Step 3: Run to verify it fails**

Run: `swift run CoreChecks`
Expected: build FAILS — `cannot find 'Geometry' in scope`.

- [ ] **Step 4: Implement `Sources/FancyZonesCore/Geometry.swift`**

```swift
import CoreGraphics

/// Pure layout math. Unless noted, rects/points use top-left-origin ("AX") coordinates, y grows downward.
public enum Geometry {
    /// AppKit (bottom-left origin, relative to the primary screen) <-> AX (top-left). Self-inverse.
    public static func flip(_ r: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    public static func flip(_ p: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: p.x, y: primaryHeight - p.y)
    }

    /// `visible` should be `screen.visibleFrame` (already excludes menu bar + Dock), in AX coords.
    public static func usableArea(visible: CGRect, inset: Double, on: Bool) -> CGRect {
        guard on else { return visible }
        let i = min(max(0, CGFloat(inset)), visible.width - 1)
        return CGRect(x: visible.minX + i, y: visible.minY, width: visible.width - i, height: visible.height)
    }

    /// Gap-free rect of a zone's cells.
    public static func cellRect(_ z: Zone, in area: CGRect) -> CGRect {
        let g = CGFloat(Zone.grid)
        return CGRect(x: area.minX + area.width * CGFloat(z.col) / g,
                      y: area.minY + area.height * CGFloat(z.row) / g,
                      width: area.width * CGFloat(z.w) / g,
                      height: area.height * CGFloat(z.h) / g)
    }

    /// Frame for a window filling the bounding box of `zones`. Sides on the grid edge inset the full `gap`,
    /// interior sides `gap/2` (so neighbors end up `gap` apart). Size is clamped to >= 1.
    public static func frame(for zones: [Zone], in area: CGRect, gap: Double) -> CGRect? {
        guard let b = Zone.bounds(of: zones) else { return nil }
        let r = cellRect(b, in: area)
        let g = CGFloat(gap)
        let l = b.col == 0 ? g : g / 2
        let t = b.row == 0 ? g : g / 2
        let rt = b.col + b.w == Zone.grid ? g : g / 2
        let bt = b.row + b.h == Zone.grid ? g : g / 2
        return CGRect(x: r.minX + l, y: r.minY + t,
                      width: max(1, r.width - l - rt), height: max(1, r.height - t - bt))
    }

    /// Index of the first zone whose gap-free cells contain `p`.
    public static func zoneIndex(at p: CGPoint, zones: [Zone], in area: CGRect) -> Int? {
        zones.firstIndex { cellRect($0, in: area).contains(p) }
    }

    /// Grid cell under `p`, or nil if outside `area`.
    public static func cell(at p: CGPoint, in area: CGRect) -> (col: Int, row: Int)? {
        guard area.contains(p) else { return nil }
        let g = Zone.grid
        let c = Int((p.x - area.minX) / area.width * CGFloat(g))
        let r = Int((p.y - area.minY) / area.height * CGFloat(g))
        return (min(max(c, 0), g - 1), min(max(r, 0), g - 1))
    }
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `swift run CoreChecks`
Expected: `all checks passed`

- [ ] **Step 6: Commit**

```bash
git add Sources/FancyZonesCore/Geometry.swift Sources/CoreChecks
git commit -m "feat: Geometry (gap math, usable area, hit testing, coordinate flip)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: App shell — status item, settings, config wiring

**Files:**
- Modify: `Package.swift` (replace whole file)
- Create: `Sources/MacFancyZones/main.swift`
- Create: `Sources/MacFancyZones/AppDelegate.swift`
- Create: `Sources/MacFancyZones/SettingsWindow.swift`

**Interfaces:**
- Consumes: `Config` (`load`, `save`, fields).
- Produces:
  - `final class SettingsWindow: NSObject, NSTextFieldDelegate { init(onChange: @escaping (Config) -> Void); func show(config: Config) }` — calls `onChange` with the edited config on every edit.
  - `final class AppDelegate` with `private var config: Config` whose `didSet` saves to disk. Tasks 6 and 7 add `editZones()` and `drag` to it (placeholders marked below).

- [ ] **Step 1: Replace `Package.swift`**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "mac-fancy-zones",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "FancyZonesCore"),
        .executableTarget(name: "CoreChecks", dependencies: ["FancyZonesCore"]),
        .executableTarget(name: "MacFancyZones", dependencies: ["FancyZonesCore"]),
        .executableTarget(name: "Probe"),
    ]
)
```

- [ ] **Step 2: Create `Sources/MacFancyZones/main.swift`**

```swift
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 3: Create `Sources/MacFancyZones/SettingsWindow.swift`**

```swift
import AppKit
import FancyZonesCore

final class SettingsWindow: NSObject, NSTextFieldDelegate {
    private var window: NSWindow?
    private var config = Config()
    private let onChange: (Config) -> Void
    private let gap = NSTextField(string: "")
    private let inset = NSTextField(string: "")
    private let toggle = NSButton(checkboxWithTitle: "Stage Manager left inset (px)", target: nil, action: nil)

    init(onChange: @escaping (Config) -> Void) {
        self.onChange = onChange
        super.init()
    }

    func show(config: Config) {
        self.config = config
        if window == nil { build() }
        gap.doubleValue = config.gap
        inset.doubleValue = config.stageManagerInset
        toggle.state = config.stageManagerOn ? .on : .off
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func build() {
        for f in [gap, inset] {
            f.delegate = self
            f.target = self
            f.action = #selector(changed)
            f.widthAnchor.constraint(equalToConstant: 80).isActive = true
        }
        toggle.target = self
        toggle.action = #selector(changed)

        let grid = NSGridView(views: [[NSTextField(labelWithString: "Gap (px)"), gap], [toggle, inset]])
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        let stack = NSStackView(views: [grid])
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "mac-fancy-zones Settings"
        w.isReleasedWhenClosed = false
        w.contentView = stack
        w.setContentSize(stack.fittingSize)
        window = w
    }

    func controlTextDidEndEditing(_ obj: Notification) { changed() }

    @objc private func changed() {
        config.gap = max(0, gap.doubleValue)
        config.stageManagerInset = max(0, inset.doubleValue)
        config.stageManagerOn = toggle.state == .on
        onChange(config)
    }
}
```

- [ ] **Step 4: Create `Sources/MacFancyZones/AppDelegate.swift`**

```swift
import AppKit
import FancyZonesCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private var config = Config.load() {
        didSet { try? config.save() }  // ponytail: silent save failure; surface in UI if it ever matters
    }
    private lazy var settings = SettingsWindow { [weak self] in self?.config = $0 }

    func applicationDidFinishLaunching(_ n: Notification) {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary)

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.split.3x3", accessibilityDescription: "mac-fancy-zones")

        let menu = NSMenu()
        // Task 6 inserts "Edit Zones…" here.
        for (title, action) in [("Settings…", #selector(showSettings)),
                                ("Accessibility Settings…", #selector(openAccessibility))] {
            let mi = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            mi.target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
    }

    @objc private func showSettings() { settings.show(config: config) }

    @objc private func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
```

- [ ] **Step 5: Build**

Run: `swift build --product MacFancyZones`
Expected: `Build complete!` (warnings about CF casts are acceptable; errors are not).

- [ ] **Step 6: Manual verification**

Run: `swift run MacFancyZones`. Expected: a grid icon appears in the menu bar, no Dock icon. Open **Settings…**, set gap to `8`, tick the Stage Manager box, set inset `120`, press Return. Then in another terminal: `cat ~/Library/Application\ Support/mac-fancy-zones/config.json` shows `"gap" : 8`, `"stageManagerInset" : 120`, `"stageManagerOn" : true`. Quit from the menu.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/MacFancyZones
git commit -m "feat: menu-bar app shell with settings window

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Zone editor

**Files:**
- Create: `Sources/MacFancyZones/ZoneEditor.swift`
- Modify: `Sources/MacFancyZones/AppDelegate.swift`

**Interfaces:**
- Consumes: `Geometry.flip/usableArea/frame/cell(at:in:)`, `Zone.spanning/contains`, `[Zone].canAdd`, `Config`.
- Produces: `final class ZoneEditor { func open(config: Config, screen: NSScreen, onSave: @escaping ([Zone]) -> Void) }`.

Behavior: full-screen dimmed overlay over the screen under the cursor, 12×12 grid drawn over the **same usable area** snapping uses (so what you draw is what you get), existing zones drawn with the gap applied. Drag across cells → add zone (rejected with a beep if it overlaps). Click (no drag) on an existing zone's cell → delete it. Return → save; Esc → cancel.

- [ ] **Step 1: Create `Sources/MacFancyZones/ZoneEditor.swift`**

```swift
import AppKit
import FancyZonesCore

private final class EditorWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

final class ZoneEditor {
    private var window: EditorWindow?

    func open(config: Config, screen: NSScreen, onSave: @escaping ([Zone]) -> Void) {
        window?.close()
        let primaryH = NSScreen.screens[0].frame.height
        let screenAX = Geometry.flip(screen.frame, primaryHeight: primaryH)
        let visibleAX = Geometry.flip(screen.visibleFrame, primaryHeight: primaryH)
        // View is flipped (top-left origin), so AX offsets relative to the screen's top-left map directly.
        let area = Geometry.usableArea(visible: visibleAX, inset: config.stageManagerInset, on: config.stageManagerOn)
            .offsetBy(dx: -screenAX.minX, dy: -screenAX.minY)

        let w = EditorWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.level = .screenSaver
        w.isOpaque = false
        w.backgroundColor = .clear
        w.isReleasedWhenClosed = false

        let view = EditorView(frame: NSRect(origin: .zero, size: screen.frame.size),
                              area: area, gap: config.gap, zones: config.zones)
        view.onDone = { [weak self, weak view] save in
            if save, let view { onSave(view.zones) }
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

private final class EditorView: NSView {
    let area: CGRect
    let gap: Double
    var zones: [Zone]
    var onDone: (Bool) -> Void = { _ in }
    private var start: (col: Int, row: Int)?
    private var current: (col: Int, row: Int)?

    init(frame: NSRect, area: CGRect, gap: Double, zones: [Zone]) {
        self.area = area
        self.gap = gap
        self.zones = zones
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirty: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()

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

        for z in zones { fill(z, NSColor.controlAccentColor.withAlphaComponent(0.55)) }
        if let s = start, let c = current {
            let p = Zone.spanning(s, c)
            fill(p, zones.canAdd(p) ? NSColor.white.withAlphaComponent(0.35) : NSColor.systemRed.withAlphaComponent(0.5))
        }

        ("Drag: add zone  ·  Click zone: delete  ·  Return: save  ·  Esc: cancel" as NSString).draw(
            at: CGPoint(x: area.minX + 12, y: area.minY + 12),
            withAttributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 14, weight: .medium)])
    }

    private func fill(_ z: Zone, _ color: NSColor) {
        guard let f = Geometry.frame(for: [z], in: area, gap: gap) else { return }
        color.setFill()
        NSBezierPath(roundedRect: f, xRadius: 6, yRadius: 6).fill()
    }

    private func cell(_ e: NSEvent) -> (col: Int, row: Int)? {
        Geometry.cell(at: convert(e.locationInWindow, from: nil), in: area)
    }

    override func mouseDown(with e: NSEvent) { start = cell(e); current = start; needsDisplay = true }

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
```

- [ ] **Step 2: Wire into `AppDelegate.swift`**

Add a property below `settings`:

```swift
    private let editor = ZoneEditor()
```

Replace the comment line `// Task 6 inserts "Edit Zones…" here.` and the `for` loop header so the menu array starts with the editor entry:

```swift
        for (title, action) in [("Edit Zones…", #selector(editZones)),
                                ("Settings…", #selector(showSettings)),
                                ("Accessibility Settings…", #selector(openAccessibility))] {
```

(delete the comment line), and add the action below `showSettings`:

```swift
    @objc private func editZones() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.screens[0]
        editor.open(config: config, screen: screen) { [weak self] zones in self?.config.zones = zones }
    }
```

- [ ] **Step 3: Build**

Run: `swift build --product MacFancyZones`
Expected: `Build complete!`

- [ ] **Step 4: Manual verification**

Run `swift run MacFancyZones`, choose **Edit Zones…**.
- Dimmed screen with a 12×12 grid inside the area below the menu bar / above the Dock (and right of the inset if the Stage Manager toggle is on).
- Drag across cells (e.g. columns 0–5, all rows) → accent-coloured zone with rounded corners and the gap visible at the edges. Drag a second one starting in columns 6–11. Preview turns red while dragging over an existing zone, and releasing there beeps and adds nothing.
- Click an existing zone → it disappears. Esc → closes, config unchanged. Redo two zones, press Return → `config.json` contains the zones. Reopen the editor → zones are shown.

- [ ] **Step 5: Commit**

```bash
git add Sources/MacFancyZones
git commit -m "feat: full-screen zone editor on the 12x12 grid

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Drag-to-snap (Shift / Shift+Ctrl)

**Files:**
- Create: `Sources/MacFancyZones/WindowAX.swift`
- Create: `Sources/MacFancyZones/ZoneOverlay.swift`
- Create: `Sources/MacFancyZones/DragSnap.swift`
- Modify: `Sources/MacFancyZones/AppDelegate.swift`

**Interfaces:**
- Consumes: `Config`, `Geometry.*`, `Zone`. Task 1's proven `order(.below, relativeTo:)` technique.
- Produces:
  - `enum WindowAX { static func window(at: CGPoint) -> AXUIElement?; static func inTitleBar(_: CGPoint, of: AXUIElement) -> Bool; static func windowID(of: AXUIElement) -> CGWindowID?; static func frame(of: AXUIElement) -> CGRect?; static func setFrame(_: CGRect, of: AXUIElement) }` (all points/rects in AX coords)
  - `final class ZoneOverlay { let screen: NSScreen; init(screen:); func update(zoneRects: [CGRect], highlighted: Set<Int>); func show(below: CGWindowID); func hide() }` — `zoneRects` are in AppKit global coordinates.
  - `final class DragSnap { var config: Config; init(config:); func start() }`

Design notes: no `flagsChanged` monitor (key-event monitoring can demand Input Monitoring). Instead, on a title-bar mouse-down a 60 Hz timer polls `NSEvent.modifierFlags` + `NSEvent.mouseLocation` until mouse-up. The window only snaps if Shift is held at release **and** the mouse moved > 4 pt since mouse-down (a Shift+click must not move anything). Ctrl must be pressed after the mouse-down (Ctrl+click is a right-click on macOS).

- [ ] **Step 1: Create `Sources/MacFancyZones/WindowAX.swift`**

```swift
import AppKit
import ApplicationServices

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
    static func setFrame(_ r: CGRect, of w: AXUIElement) {
        var size = r.size, origin = r.origin
        guard let sv = AXValueCreate(.cgSize, &size), let pv = AXValueCreate(.cgPoint, &origin) else { return }
        AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, sv)
        AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, pv)
        AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, sv)
    }
}
```

- [ ] **Step 2: Create `Sources/MacFancyZones/ZoneOverlay.swift`**

```swift
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
    func hide() { window.orderOut(nil) }
}

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
```

- [ ] **Step 3: Create `Sources/MacFancyZones/DragSnap.swift`**

```swift
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
    }

    private func monitor(_ mask: NSEvent.EventTypeMask, _ handler: @escaping () -> Void) {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { _ in handler() }) { monitors.append(m) }
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
              let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) else {
            hideOverlay()
            return
        }
        if overlay?.screen !== screen {
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
        if let f = Geometry.frame(for: zones, in: area, gap: config.gap) { WindowAX.setFrame(f, of: t.el) }
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
```

- [ ] **Step 4: Wire into `AppDelegate.swift`**

Add the property below `editor`:

```swift
    private lazy var drag = DragSnap(config: config)
```

Replace the `config` property so changes propagate to the live `DragSnap`:

```swift
    private var config = Config.load() {
        didSet {
            try? config.save()  // ponytail: silent save failure; surface in UI if it ever matters
            drag.config = config
        }
    }
```

And at the end of `applicationDidFinishLaunching`, after `item.menu = menu`, add:

```swift
        drag.start()
```

- [ ] **Step 5: Build**

Run: `swift build --product MacFancyZones`
Expected: `Build complete!`

- [ ] **Step 6: Manual verification (human required)**

Run `swift run MacFancyZones` (grant Accessibility to the terminal app, then restart). In **Edit Zones…** make: left half (cols 0–5, all rows), top-right quarter, bottom-right quarter. Settings: gap 10. Open two Finder windows plus a Terminal. Check each:

1. Drag a Finder window by the title bar **without** Shift: nothing appears; window moves normally.
2. Hold Shift mid-drag: translucent zones appear **behind the dragged window**, over the other windows; the zone under the cursor is brighter. Release Shift → zones vanish.
3. Shift-drag into the left zone and release: window fills the left half with 10 px at screen edges; drop another window in the top-right zone: exactly 10 px between the two windows and 10 px to the screen edges. Menu bar / Dock are not covered.
4. Hold Shift, then also Ctrl, sweep across the two right zones, release: window fills the union of both right zones. Release Ctrl mid-drag → selection collapses to the hovered zone.
5. Shift+click a title bar without moving: window does not move.
6. Delete all zones in the editor, save, Shift-drag: nothing shown, window not moved.
7. Enable Stage Manager (System Settings → Desktop & Dock) + settings toggle with inset ~100: left zone starts right of the Stage Manager strip; tune the inset value until the strip is fully visible.
8. If a second display is available: Shift-drag onto it; zones appear on that display and the window snaps there.

If any check fails, fix before committing; capture the fix in this task's commit.

- [ ] **Step 7: Commit**

```bash
git add Sources/MacFancyZones
git commit -m "feat: Shift / Shift+Ctrl drag-to-snap with overlay behind dragged window

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Bundle script, README, remove probe

**Files:**
- Modify: `Package.swift` (replace whole file)
- Delete: `Sources/Probe/`
- Create: `scripts/bundle.sh`
- Create: `README.md`

**Interfaces:**
- Consumes: product `MacFancyZones`.
- Produces: `scripts/bundle.sh` → `build/mac-fancy-zones.app` (ad-hoc signed, `LSUIElement`), so the Accessibility grant attaches to the app instead of Terminal.

- [ ] **Step 1: Delete the probe and replace `Package.swift`**

Run: `git rm -r Sources/Probe`

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "mac-fancy-zones",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "FancyZonesCore"),
        .executableTarget(name: "CoreChecks", dependencies: ["FancyZonesCore"]),
        .executableTarget(name: "MacFancyZones", dependencies: ["FancyZonesCore"]),
    ]
)
```

- [ ] **Step 2: Create `scripts/bundle.sh`**

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product MacFancyZones
bin="$(swift build -c release --show-bin-path)"

app=build/mac-fancy-zones.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin/MacFancyZones" "$app/Contents/MacOS/mac-fancy-zones"

cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>mac-fancy-zones</string>
    <key>CFBundleIdentifier</key><string>com.dlambert.mac-fancy-zones</string>
    <key>CFBundleName</key><string>mac-fancy-zones</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
EOF

codesign --force --sign - "$app"
echo "built $app"
```

Run: `chmod +x scripts/bundle.sh`

- [ ] **Step 3: Create `README.md`**

```markdown
# mac-fancy-zones

Ultra-light zone-based window manager for macOS. Native Swift, menu-bar only.

## Use
- **Edit Zones…** (menu bar icon): drag across the 12×12 grid to add a zone, click a zone to delete, Return saves, Esc cancels.
- **Settings…**: gap between zones / at screen edges (px), and a manual left inset for Stage Manager.
- Drag a window by its title bar and hold **Shift** → zones appear; drop in one to snap.
- Hold **Shift+Ctrl** (press Ctrl after starting the drag) → sweep several zones; the window fills them all.
- Config: `~/Library/Application Support/mac-fancy-zones/config.json`.

## Build
- `swift run CoreChecks` — core logic checks (no Xcode needed; XCTest is unavailable with only the Command Line Tools).
- `scripts/bundle.sh` → `build/mac-fancy-zones.app`. Open it and grant Accessibility.
  The ad-hoc signature changes on every rebuild, so macOS may ask you to re-grant Accessibility
  (remove and re-add the app in System Settings → Privacy & Security → Accessibility).
```

- [ ] **Step 4: Verify**

Run: `swift run CoreChecks`
Expected: `all checks passed`

Run: `scripts/bundle.sh`
Expected: ends with `built build/mac-fancy-zones.app`

Run: `open build/mac-fancy-zones.app`, grant Accessibility when prompted, quit and reopen if needed. Expected: menu-bar icon, no Dock icon, and the Task 7 manual checks 2–3 still work.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: app bundle script, README, remove spike probe

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```
