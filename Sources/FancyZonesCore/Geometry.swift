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

    /// Linear interpolation between two rects; `t` is clamped to 0...1.
    public static func lerp(from a: CGRect, to b: CGRect, t: Double) -> CGRect {
        let k = CGFloat(min(1, max(0, t)))
        return CGRect(x: a.minX + (b.minX - a.minX) * k, y: a.minY + (b.minY - a.minY) * k,
                      width: a.width + (b.width - a.width) * k, height: a.height + (b.height - a.height) * k)
    }

    /// Cubic ease-out: fast start, gentle landing. 0 -> 0, 1 -> 1.
    public static func easeOut(_ t: Double) -> Double {
        let u = 1 - min(1, max(0, t))
        return 1 - u * u * u
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
