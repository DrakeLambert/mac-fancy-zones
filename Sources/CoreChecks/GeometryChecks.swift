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

    // animation math
    let a = CGRect(x: 0, y: 0, width: 100, height: 100)
    let b = CGRect(x: 200, y: 100, width: 300, height: 500)
    check(nearRect(Geometry.lerp(from: a, to: b, t: 0), a), "lerp t=0 is start")
    check(nearRect(Geometry.lerp(from: a, to: b, t: 1), b), "lerp t=1 is end")
    check(nearRect(Geometry.lerp(from: a, to: b, t: 0.5), CGRect(x: 100, y: 50, width: 200, height: 300)), "lerp midpoint")
    check(nearRect(Geometry.lerp(from: a, to: b, t: 2), b), "lerp clamps t above 1")
    check(nearRect(Geometry.lerp(from: a, to: b, t: -1), a), "lerp clamps t below 0")
    check(near(Geometry.easeOut(0), 0) && near(Geometry.easeOut(1), 1), "ease endpoints")
    check(Geometry.easeOut(0.5) > 0.5, "ease-out is front-loaded")
    check(Geometry.easeOut(0.3) < Geometry.easeOut(0.6), "ease-out is monotonic")
}
