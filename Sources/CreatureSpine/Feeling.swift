import Foundation

// MARK: - Creature ID

/// Unique identifier for a creature instance.
public struct CreatureID: Hashable, Sendable {
    public let value: UUID

    public init() { self.value = UUID() }
    public init(_ uuid: UUID) { self.value = uuid }
}

// MARK: - Feeling Kind

/// The vocabulary of creature signals. Bidirectional: creature→conscious and conscious→creature.
public enum FeelingKind: Int, CaseIterable, Sendable, Hashable {
    case warmth       // Attraction, comfort, safety
    case pull         // Directional draw toward a coordinate
    case unease       // Something wrong, anomaly detected
    case recognition  // Pattern match, familiar territory
    case novelty      // Unexplored, information gain
    case friction     // Resistance, impedance, difficulty
    case spark        // Insight, synthesis, breakthrough
    case resonance    // Multiple signals aligning harmonically
    case drift        // Entropy, losing coordinate lock
}

// MARK: - Feeling

/// A single signal emitted by a creature or sent by the conscious layer.
public struct Feeling: Sendable {
    public let kind: FeelingKind
    public let intensity: Float
    public let source: CreatureID
    public let coordinate: SpineCoordinate
    public let timestamp: ContinuousClock.Instant

    public init(
        kind: FeelingKind,
        intensity: Float,
        source: CreatureID,
        coordinate: SpineCoordinate
    ) {
        self.kind = kind
        self.intensity = intensity.clamped(to: 0...1)
        self.source = source
        self.coordinate = coordinate
        self.timestamp = ContinuousClock.now
    }
}

// MARK: - Feeling Vector

/// A vector in feeling-space. One float per FeelingKind dimension.
/// Used for wave interference summation in the signal bus.
public struct FeelingVector: Sendable {
    private var components: [Float]

    public init() {
        self.components = Array(repeating: 0, count: FeelingKind.allCases.count)
    }

    public subscript(kind: FeelingKind) -> Float {
        get { components[kind.rawValue] }
        set { components[kind.rawValue] = newValue }
    }

    /// Euclidean magnitude of the vector.
    public var magnitude: Float {
        sqrt(components.reduce(0) { $0 + $1 * $1 })
    }

    /// The dominant feeling (highest absolute component).
    public var dominant: FeelingKind? {
        guard let maxIdx = components.indices.max(by: { abs(components[$0]) < abs(components[$1]) }),
              abs(components[maxIdx]) > 0.001 else { return nil }
        return FeelingKind(rawValue: maxIdx)
    }

    public static func + (lhs: FeelingVector, rhs: FeelingVector) -> FeelingVector {
        var result = FeelingVector()
        for i in result.components.indices {
            result.components[i] = lhs.components[i] + rhs.components[i]
        }
        return result
    }
}
