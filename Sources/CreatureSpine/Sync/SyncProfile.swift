import Foundation

/// The result of a sync calibration between two LLM partners.
public struct SyncProfile: Sendable, Codable {
    /// Unique identifier for this sync configuration
    public let id: String

    /// When this profile was created
    public let createdAt: Date

    /// Metadata for partner A (typically the conscious slot)
    public let partnerA: PartnerMetadata

    /// Metadata for partner B (typically the unconscious slot)
    public let partnerB: PartnerMetadata

    /// Which role partner A is calibrated for
    public let roleA: PartnerRole

    /// Which role partner B is calibrated for
    public let roleB: PartnerRole

    /// Confidence scores for each role (0-1)
    public let confidenceConscious: Float
    public let confidenceUnconscious: Float

    /// Latency differential (positive = A is slower)
    public let latencyDeltaMs: Double

    /// Whether the pair is considered "in sync"
    public let isInSync: Bool

    /// Routing weights: how much to trust each partner for each role
    public let consciousWeightA: Float  // 0-1, higher = A handles more conscious tasks
    public let unconsciousWeightA: Float  // 0-1, higher = A handles more unconscious tasks

    /// Number of tests used for calibration
    public let testCount: Int

    public init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        partnerA: PartnerMetadata,
        partnerB: PartnerMetadata,
        roleA: PartnerRole,
        roleB: PartnerRole,
        confidenceConscious: Float,
        confidenceUnconscious: Float,
        latencyDeltaMs: Double,
        isInSync: Bool,
        consciousWeightA: Float,
        unconsciousWeightA: Float,
        testCount: Int
    ) {
        self.id = id
        self.createdAt = createdAt
        self.partnerA = partnerA
        self.partnerB = partnerB
        self.roleA = roleA
        self.roleB = roleB
        self.confidenceConscious = confidenceConscious
        self.confidenceUnconscious = confidenceUnconscious
        self.latencyDeltaMs = latencyDeltaMs
        self.isInSync = isInSync
        self.consciousWeightA = consciousWeightA
        self.unconsciousWeightA = unconsciousWeightA
        self.testCount = testCount
    }

    /// How close to 0.5 a routing weight must sit before the pair is judged to *share*
    /// ownership of a role rather than one partner owning it.
    public static let coordinationTolerance: Float = 0.1

    /// True when the calibrated pair spans both bases (`isInSync`) **and** neither
    /// partner clearly owns this role — the weight sits near 0.5.
    ///
    /// This is the case `route(for:)` handles worst: it thresholds a continuous
    /// amplitude at `>= 0.5`, so 0.51 and 0.99 collapse identically and the other
    /// partner's half of the answer is discarded. When the pair genuinely shares the
    /// task, both phases should be read out instead of one being thrown away.
    public func shouldCoordinate(for role: PartnerRole) -> Bool {
        guard isInSync else { return false }
        let weight = role == .conscious ? consciousWeightA : unconsciousWeightA
        return abs(weight - 0.5) <= Self.coordinationTolerance
    }

    /// Determine which partner should handle a task.
    public func route(for role: PartnerRole) -> (partner: PartnerRole, confidence: Float) {
        if role == .conscious {
            let useA = consciousWeightA >= 0.5
            let confidence = useA ? consciousWeightA : (1 - consciousWeightA)
            return (useA ? roleA : roleB, confidence)
        } else {
            let useA = unconsciousWeightA >= 0.5
            let confidence = useA ? unconsciousWeightA : (1 - unconsciousWeightA)
            return (useA ? roleA : roleB, confidence)
        }
    }

    /// Get the partner metadata for a role.
    public func partner(for role: PartnerRole) -> PartnerMetadata {
        return role == roleA ? partnerA : partnerB
    }

    /// Save profile to JSON.
    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        try data.write(to: url)
    }

    /// Load profile from JSON.
    public static func load(from url: URL) throws -> SyncProfile {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SyncProfile.self, from: data)
    }
}

extension SyncProfile {
    /// Human-readable summary.
    public var summary: String {
        var lines: [String] = []
        lines.append("Sync Profile: " + String(id.prefix(8)))
        lines.append("==================")
        lines.append("")
        lines.append("Partner A (\(roleA.rawValue)): \(partnerA.name)")
        lines.append("Partner B (\(roleB.rawValue)): \(partnerB.name)")
        lines.append("")
        lines.append("Confidence:")
        lines.append("  Conscious: \(String(format: "%.1f%%", confidenceConscious * 100))")
        lines.append("  Unconscious: \(String(format: "%.1f%%", confidenceUnconscious * 100))")
        lines.append("")
        lines.append("Latency Delta: \(String(format: "%.0f", latencyDeltaMs))ms")
        lines.append("Status: \(isInSync ? "IN SYNC" : "NEEDS ATTENTION")")
        return lines.joined(separator: "\n")
    }
}
