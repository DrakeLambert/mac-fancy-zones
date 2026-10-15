# mac-fancy-zones — Design

Ultra-light, zone-based window manager for macOS (like PowerToys FancyZones). Native Swift, menu-bar-only app.

## Goals
- Define rectangular zones on a 12×12 grid; one layout, applied to all displays.
- Hold Shift while dragging a window by its title bar → zones appear; drop in a zone to snap.
- Hold Shift+Ctrl → span multiple zones; window fills their union.
- Respect menu bar, Dock, and a manual Stage Manager left inset.
- Configurable pixel gap between zones and at screen edges.

## Non-goals
Multiple layouts, per-display layouts, hotkey snapping, animations, launch-at-login (later via `SMAppService`), Stage Manager auto-detection.

## Shape
Menu-bar-only app (`LSUIElement`). SwiftPM/Xcode project, ~5 small files. Needs Accessibility permission (prompt on first launch).

## Data
`~/Library/Application Support/mac-fancy-zones/config.json`:
```json
{ "gap": 5, "stageManagerInset": 100, "stageManagerOn": true,
  "zones": [ {"col":0,"row":0,"w":4,"h":12} ] }
```
Missing file → defaults (gap 5, inset 100, toggle off, no zones). Rewritten on editor save. Zones are grid cells, so they scale to any display. Zones must not overlap (validated on create and on load).

## Geometry (pure, unit-tested)
- Usable area = `screen.visibleFrame` (excludes menu bar + Dock) minus left inset when Stage Manager toggle is on.
- Zone rect = grid cells carved from usable area.
- Gap: interior sides inset `gap/2` each (neighbors end up `gap` apart); sides touching usable-area edge inset the full `gap`.
- Multi-zone span = union of zone rects, same gap rule applied to the union.

## Drag-to-snap
- Global `NSEvent` monitors (listen-only): mouse down/drag/up + modifier changes. No `CGEventTap`.
- Mouse down: `AXUIElementCopyElementAtPosition` → window under cursor; arm only if click is in the window's title-bar strip (heuristic; tunable height).
- Shift held while dragging: show translucent click-through overlay on the screen under the cursor, one view per zone; zone under cursor brightens.
- Shift+Ctrl: track zones swept; highlight the union.
- **Overlay is behind the dragged window**: overlay `NSWindow`s stay at normal level and are ordered `.below` the dragged window's `CGWindowID` (obtained via `_AXUIElementGetWindow`, fallback `CGWindowListCopyWindowInfo` match by pid + bounds). Re-asserted each drag tick. Overlay covers other windows but never the dragged one.
- Mouse up with Shift held: set window AX position + size to the target frame. Shift released before mouse up → no snap.
- Multi-display: same zone fractions applied to the screen under the cursor.

## Zone editor
- Opened from menu-bar item; full-screen overlay with 12×12 grid.
- Drag across cells to create a zone; overlapping drags rejected. Click a zone to delete. Edge-drag resize is last/nice-to-have.
- Esc cancels; Enter/Save writes JSON.
- Small settings panel: gap, Stage Manager inset, Stage Manager toggle.

## Testing
Unit tests: geometry (gap math, spans, insets) and overlap validation. Drag/overlay verified manually (needs real screen + Accessibility).

## Risks
- **Cross-app overlay ordering** (`order(.below, relativeTo:)` on another process's window) is unverified. First plan task: throwaway probe dragging a Finder window. Fallback if it fails: outline-only floating overlay (draws over dragged window) — requires user sign-off.
- Apps (Electron etc.) may refuse AX resize or enforce min sizes; snap as close as allowed, don't fight.
- Title-bar hit-test is heuristic; custom title bars may need a taller strip.
