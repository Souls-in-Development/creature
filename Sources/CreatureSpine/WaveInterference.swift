import Foundation

/// The result of wave interference at a coordinate.
/// The conscious layer reads this instead of raw individual creature feelings.
public struct ResolvedSignal: Sendable {
    /// The summed feeling vector (constructive/destructive superposition).
    public let vector: FeelingVector
    /// Whether there is significant tension (conflicting creature signals).
    public let isTense: Bool
    /// Number of creatures contributing to this signal.
    public let creatureCount: Int
    /// Coordinate where the interference was resolved.
    public let coordinate: SpineCoordinate
}

/// Wave interference resolver. Accumulates feelings per coordinate,
/// sums them as vectors, detects tension from conflicting signals.
///
/// This IS the subconscious's "physics" — pattern matching without interpretation.
/// No decisions. Just superposition.
public struct WaveResolver: Sendable {
    private var feelings: [String: [Feeling]] = [:]

    public init() {}

    /// Add a feeling to the interference buffer.
    public mutating func add(_ feeling: Feeling) {
        let key = feeling.coordinate.stringKey
        feelings[key, default: []].append(feeling)
    }

    /// Resolve interference at a coordinate. Returns the summed vector + tension flag.
    public func resolve(at coordinate: SpineCoordinate) -> ResolvedSignal {
        let key = coordinate.stringKey
        let batch = feelings[key] ?? []

        guard !batch.isEmpty else {
            return ResolvedSignal(
                vector: FeelingVector(),
                isTense: false,
                creatureCount: 0,
                coordinate: coordinate
            )
        }

        // Sum feelings into a vector
        var sumVector = FeelingVector()
        for feeling in batch {
            sumVector[feeling.kind] = sumVector[feeling.kind] + feeling.intensity
        }

        // Detect tension: count distinct non-zero dimensions
        let activeDimensions = FeelingKind.allCases.filter { abs(sumVector[$0]) > 0.01 }
        let isTense = activeDimensions.count >= 2 && hasTension(batch)

        return ResolvedSignal(
            vector: sumVector,
            isTense: isTense,
            creatureCount: batch.count,
            coordinate: coordinate
        )
    }

    /// Clear all accumulated feelings.
    public mutating func clear() {
        feelings.removeAll()
    }

    /// All coordinates with pending feelings.
    public var activeCoordinates: [SpineCoordinate] {
        feelings.compactMap { (_, batch) in
            batch.first?.coordinate
        }
    }

    // MARK: - Private

    /// Tension exists when different creatures push in different feeling directions.
    /// Measured by checking if the per-creature dominant feelings disagree.
    private func hasTension(_ batch: [Feeling]) -> Bool {
        let kinds = Set(batch.map(\.kind))
        // If we have both "positive" and "negative" valence feelings, that's tension.
        let positive: Set<FeelingKind> = [.warmth, .recognition, .spark, .resonance]
        let negative: Set<FeelingKind> = [.unease, .friction, .drift]
        let hasPositive = !kinds.isDisjoint(with: positive)
        let hasNegative = !kinds.isDisjoint(with: negative)
        return hasPositive && hasNegative
    }
}
