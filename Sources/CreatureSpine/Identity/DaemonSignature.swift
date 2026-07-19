import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
// Apple's own cross-platform implementation of the same API (swift-crypto).
// Only SHA-256 is used, and it is source-identical on both.
import Crypto
#endif

/// Living signature from creature colour emissions.
/// No storage needed — the emission pattern IS the identity.
/// The signature hash is deterministic from the emission sequence.
/// Copying would require reproducing the entire emission history in order.
public final class DaemonSignature: @unchecked Sendable {
    private let lock = NSLock()

    /// Running SHA-256 hash state built incrementally from emissions.
    /// Each emission feeds (hue, saturation, value, pattern) bytes into the hash.
    private var hashData = Data()

    /// Current pattern index (0-255) — evolves with each emission.
    public private(set) var currentPattern: UInt8 = 0

    /// Total number of emissions recorded.
    public private(set) var emissionCount: Int = 0

    /// Circular buffer of recent emissions for verification.
    private var recentBuffer: [ColourTrack] = []
    private let maxRecent = 100

    public init() {}

    /// Record a colour emission. Pattern evolves, hash updates.
    public func emit(_ track: ColourTrack) {
        lock.lock()
        defer { lock.unlock() }

        // Append emission data to running hash input
        appendTrackData(track)
        emissionCount += 1

        // Evolve pattern
        currentPattern = evolvePattern(track)

        // Circular buffer for recent emissions
        if recentBuffer.count >= maxRecent {
            recentBuffer.removeFirst()
        }
        recentBuffer.append(track)
    }

    /// SHA-256 hash of the entire emission history.
    /// Deterministic: same emissions in same order = same hash.
    public var signatureHash: String {
        lock.lock()
        defer { lock.unlock() }
        let digest = SHA256.hash(data: hashData)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Get recent emissions for verification (up to `count`, most recent last).
    public func recentEmissions(count: Int) -> [ColourTrack] {
        lock.lock()
        defer { lock.unlock() }
        return Array(recentBuffer.suffix(count))
    }

    // MARK: - Private

    private func appendTrackData(_ track: ColourTrack) {
        // Feed colour components + pattern into running hash data
        withUnsafeBytes(of: track.hue) { hashData.append(contentsOf: $0) }
        withUnsafeBytes(of: track.saturation) { hashData.append(contentsOf: $0) }
        withUnsafeBytes(of: track.value) { hashData.append(contentsOf: $0) }
        hashData.append(track.creatureMarking.pattern)
    }

    private func evolvePattern(_ track: ColourTrack) -> UInt8 {
        // Pattern evolves based on cumulative emission characteristics
        // XOR current pattern with emission data for deterministic evolution
        let hueByte = UInt8(truncatingIfNeeded: Int(track.hue) % 256)
        let satByte = UInt8(track.saturation * 255)
        let valByte = UInt8(track.value * 255)
        return currentPattern ^ hueByte ^ satByte ^ valByte ^ track.creatureMarking.pattern
    }
}
