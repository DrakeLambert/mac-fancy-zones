import Foundation

public struct Config: Codable, Equatable {
    public var gap: Double = 5
    public var stageManagerInset: Double = 100
    public var stageManagerOn: Bool = false
    public var zones: [Zone] = []
    public var animate: Bool = true

    public init() {}

    enum CodingKeys: String, CodingKey { case gap, stageManagerInset, stageManagerOn, zones, animate }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gap = try c.decodeIfPresent(Double.self, forKey: .gap) ?? gap
        stageManagerInset = try c.decodeIfPresent(Double.self, forKey: .stageManagerInset) ?? stageManagerInset
        stageManagerOn = try c.decodeIfPresent(Bool.self, forKey: .stageManagerOn) ?? stageManagerOn
        zones = try c.decodeIfPresent([Zone].self, forKey: .zones) ?? zones
        animate = try c.decodeIfPresent(Bool.self, forKey: .animate) ?? animate
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

    /// Copy with the settings fields replaced (negatives clamped to 0); zones untouched.
    public func with(gap: Double, stageManagerInset: Double, stageManagerOn: Bool, animate: Bool) -> Config {
        var c = self
        c.gap = max(0, gap)
        c.stageManagerInset = max(0, stageManagerInset)
        c.stageManagerOn = stageManagerOn
        c.animate = animate
        return c
    }

    public func save(to url: URL = Config.defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: url, options: .atomic)
    }
}
