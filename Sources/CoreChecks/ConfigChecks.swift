import Foundation
import FancyZonesCore

func configChecks() {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mfz-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("config.json")

    check(Config.load(from: url) == Config(), "missing file -> defaults")
    let d = Config()
    check(d.gap == 5 && d.stageManagerInset == 100 && !d.stageManagerOn && d.zones.isEmpty, "default values")
    check(d.animate, "animation defaults on")

    var c = Config()
    c.gap = 8
    c.animate = false
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

    // settings edits must not touch zones (stale-copy data loss)
    var base = Config()
    base.zones = [Zone(col: 0, row: 0, w: 4, h: 12)]
    let edited = base.with(gap: 9, stageManagerInset: -5, stageManagerOn: true, animate: false)
    check(edited.zones == base.zones, "settings edit keeps zones")
    check(edited.gap == 9 && edited.stageManagerInset == 0 && edited.stageManagerOn && !edited.animate,
          "settings applied, negatives clamped")

    try! Data("not json {".utf8).write(to: url)
    check(Config.load(from: url) == Config(), "corrupt file -> defaults")
    check(!FileManager.default.fileExists(atPath: url.path), "corrupt file moved aside")
    check(FileManager.default.contents(atPath: url.path + ".corrupt") == Data("not json {".utf8),
          "corrupt content preserved")
}
