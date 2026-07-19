import Foundation

/// On-disk configuration: the two cognitive slots (conscious/unconscious), each
/// a local MLX model id or a remote endpoint (see `SlotProvider`), plus the path
/// to the learned sync profile. A single flat, backward-compatible shape.
public struct CreatureConfig: Codable, Sendable {
    public var consciousURL: String
    public var consciousKey: String
    public var consciousModel: String
    public var unconsciousURL: String
    public var unconsciousKey: String
    public var unconsciousModel: String
    public var profilePath: String

    public static let defaultPath = "\(NSHomeDirectory())/.creature/config.json"
    public static let defaultProfilePath = "\(NSHomeDirectory())/.creature/sync-profile.json"

    public init(
        consciousURL: String,
        consciousKey: String,
        consciousModel: String,
        unconsciousURL: String,
        unconsciousKey: String,
        unconsciousModel: String,
        profilePath: String
    ) {
        self.consciousURL = consciousURL
        self.consciousKey = consciousKey
        self.consciousModel = consciousModel
        self.unconsciousURL = unconsciousURL
        self.unconsciousKey = unconsciousKey
        self.unconsciousModel = unconsciousModel
        self.profilePath = profilePath
    }

    public static func load() -> CreatureConfig? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: defaultPath)) else { return nil }
        return try? JSONDecoder().decode(CreatureConfig.self, from: data)
    }

    public func save() throws {
        let dir = URL(fileURLWithPath: Self.defaultPath).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: URL(fileURLWithPath: Self.defaultPath))
    }
}
