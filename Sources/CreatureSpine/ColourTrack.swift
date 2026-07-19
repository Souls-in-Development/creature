import Foundation

// MARK: - Creature Marking

/// Distinct visual marking per creature type — splotch, pattern, stamp.
/// Each creature type leaves identifiable footprints.
public struct CreatureMarking: Hashable, Sendable {
    /// Human-readable creature type name.
    public let name: String
    /// Pattern index (maps to a stamp texture for rendering).
    public let pattern: UInt8

    public init(name: String, pattern: UInt8) {
        self.name = name
        self.pattern = pattern
    }
}

// MARK: - Colour Track

/// A single colour emission at a coordinate. The footprint a creature leaves
/// when it reacts — a byproduct, not an intentional act.
///
/// - hue: from daemon key (identity)
/// - saturation: reaction intensity
/// - value: engagement energy
public struct ColourTrack: Sendable {
    public let coordinate: SpineCoordinate
    public let hue: Float         // 0-360, from daemon key
    public let saturation: Float  // 0-1, reaction intensity
    public let value: Float       // 0-1, engagement energy
    public let creatureMarking: CreatureMarking
    public let timestamp: ContinuousClock.Instant

    public init(
        coordinate: SpineCoordinate,
        hue: Float,
        saturation: Float,
        value: Float,
        creatureMarking: CreatureMarking
    ) {
        self.coordinate = coordinate
        self.hue = Float(Double(hue).clamped(to: 0...360))
        self.saturation = saturation.clamped(to: 0...1)
        self.value = value.clamped(to: 0...1)
        self.creatureMarking = creatureMarking
        self.timestamp = ContinuousClock.now
    }

    /// Convenience: build from a creature reaction event.
    public static func fromReaction(
        coordinate: SpineCoordinate,
        daemonKeyHue: Float,
        reactionIntensity: Float,
        energy: Float,
        creatureMarking: CreatureMarking
    ) -> ColourTrack {
        ColourTrack(
            coordinate: coordinate,
            hue: daemonKeyHue,
            saturation: reactionIntensity,
            value: energy,
            creatureMarking: creatureMarking
        )
    }
}
