import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
// Apple's own cross-platform implementation of the same API (swift-crypto).
// Only SHA-256 is used, and it is source-identical on both.
import Crypto
#endif

// MARK: - Memory Dimensions

/// Multimodal dimensions of a memory — how it was experienced.
public struct MemoryDimensions: Hashable, Sendable, Codable {
    public var visual: Float
    public var auditory: Float
    public var emotional: Float
    public var somatic: Float
    public var semantic: Float

    public init(
        visual: Float = 0, auditory: Float = 0,
        emotional: Float = 0, somatic: Float = 0, semantic: Float = 0
    ) {
        self.visual = visual
        self.auditory = auditory
        self.emotional = emotional
        self.somatic = somatic
        self.semantic = semantic
    }
}

// MARK: - Memory Orbit

/// A shared memory modelled as a Keplerian orbit.
/// Semi-major axis = importance, eccentricity = volatility,
/// orbital period = recall cycle (days).
public struct MemoryOrbit: Hashable, Sendable, Codable {
    public let label: String
    public let semiMajorAxis: Float   // 0-1: importance
    public let eccentricity: Float    // 0-1: volatility (0 = circular/steady, 1 = wild swings)
    public let orbitalPeriod: Float   // Days per full orbit
    public let dimensions: MemoryDimensions

    public init(
        label: String, semiMajorAxis: Float, eccentricity: Float,
        orbitalPeriod: Float, dimensions: MemoryDimensions
    ) {
        self.label = label
        self.semiMajorAxis = max(0, min(1, semiMajorAxis))
        self.eccentricity = max(0, min(0.99, eccentricity))
        self.orbitalPeriod = max(0.1, orbitalPeriod)
        self.dimensions = dimensions
    }

    /// Closest approach — memory at its most vivid.
    public var perihelion: Float { semiMajorAxis * (1 - eccentricity) }

    /// Farthest point — memory at its most faded.
    public var aphelion: Float { semiMajorAxis * (1 + eccentricity) }

    /// Vividness at a given orbital phase (0 = perihelion, π = aphelion).
    /// Returns 0-1 where 1 = maximally vivid.
    public func vividness(atPhase phase: Float) -> Float {
        // Radius at phase (Kepler orbit equation simplified)
        let r = semiMajorAxis * (1 - eccentricity * eccentricity) /
                (1 + eccentricity * cos(phase))
        // Vividness is inverse of radius, normalized
        let maxR = aphelion
        let minR = perihelion
        guard maxR > minR else { return semiMajorAxis }
        return 1.0 - (r - minR) / (maxR - minR)
    }

    /// Current orbital phase given elapsed days since orbit start.
    public func phase(atDay day: Float) -> Float {
        let fraction = day.truncatingRemainder(dividingBy: orbitalPeriod) / orbitalPeriod
        return fraction * 2 * .pi
    }
}

// MARK: - Memory Orbit System

/// Collection of memory orbits forming the Human Key.
/// The vividness pattern at any moment is unique — it's a function of
/// which memories exist, their orbital parameters, and the current time.
public struct MemoryOrbitSystem: Sendable, Codable {
    private var orbits: [MemoryOrbit] = []
    /// Reference date for orbital phase calculation.
    public var epoch: Date

    public init(epoch: Date = Date(timeIntervalSince1970: 0)) {
        self.epoch = epoch
    }

    public mutating func add(_ orbit: MemoryOrbit) {
        orbits.append(orbit)
    }

    public var count: Int { orbits.count }

    public func orbit(labeled label: String) -> MemoryOrbit? {
        orbits.first { $0.label == label }
    }

    public var allOrbits: [MemoryOrbit] { orbits }

    /// Snapshot of vividness for all memories at a given moment.
    public func vividnessSnapshot(at date: Date) -> [String: Float] {
        let days = Float(date.timeIntervalSince(epoch)) / 86400.0
        var snapshot: [String: Float] = [:]
        for orbit in orbits {
            let phase = orbit.phase(atDay: days)
            snapshot[orbit.label] = orbit.vividness(atPhase: phase)
        }
        return snapshot
    }

    /// Derive a 32-byte key from the current orbital state.
    /// This is the Human Key — unique because it depends on all memory
    /// orbits' positions at the exact moment, which evolve continuously.
    public func deriveKey(at date: Date) -> Data {
        let snapshot = vividnessSnapshot(at: date)
        // Sort by label for determinism, then hash the vividness pattern
        let sorted = snapshot.sorted { $0.key < $1.key }
        var hasher = SHA256()
        for (label, vividness) in sorted {
            hasher.update(data: Data(label.utf8))
            var v = vividness
            hasher.update(data: Data(bytes: &v, count: MemoryLayout<Float>.size))
        }
        // Include epoch for uniqueness
        var epochInterval = epoch.timeIntervalSince1970
        hasher.update(data: Data(bytes: &epochInterval, count: MemoryLayout<TimeInterval>.size))

        let digest = hasher.finalize()
        return Data(digest)
    }
}
