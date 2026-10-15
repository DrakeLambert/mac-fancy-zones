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
