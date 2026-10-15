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
