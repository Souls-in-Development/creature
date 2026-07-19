import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
// Apple's own cross-platform implementation of the same API (swift-crypto).
// Only SHA-256 is used, and it is source-identical on both.
import Crypto
#endif

/// A snapshot of the accumulated trail pattern — the AI's emergent identity.
///
/// - Evolves: creatures keep reacting, leaving new trails.
/// - Unique: no two AIs have the same reaction history.
/// - Unfakeable: reproducing it requires replaying the entire history.
/// - Crypto-bound: hue family comes from Ed25519 daemon key.
///
/// This is a behavioural fingerprint (proof-of-history), not a primary
/// cryptographic identity. The three-key system is the real identity layer.
public struct TrailSignature: Sendable {
    /// SHA-256 hash of the density map state.
    public let snapshotHash: Data
    /// Daemon key hue that produced this trail family.
    public let daemonKeyHue: Float
    /// Number of coordinates with trail data.
    public let coordinateCount: Int
    /// Total density across all coordinates.
    public let totalDensity: Float
    /// Dominant hue across the trail (circular mean). nil if no data.
    public let dominantHue: Float?
    /// Which creature markings appear in the trail.
    public let markings: Set<CreatureMarking>
    /// When this snapshot was taken.
    public let timestamp: ContinuousClock.Instant

    /// Take a snapshot of the current trail state.
    public static func snapshot(
        from accumulator: TrailAccumulator,
        daemonKeyHue: Float
    ) -> TrailSignature {
        let densityMap = accumulator.densityMap()

        // Compute hash from sorted density map for determinism
        var hasher = SHA256()
        for key in densityMap.keys.sorted() {
            hasher.update(data: Data(key.utf8))
            var density = densityMap[key]!
            withUnsafeBytes(of: &density) { hasher.update(bufferPointer: $0) }
        }
        var hue = daemonKeyHue
        withUnsafeBytes(of: &hue) { hasher.update(bufferPointer: $0) }
        let hash = Data(hasher.finalize())

        let totalDensity = densityMap.values.reduce(0, +)

        return TrailSignature(
            snapshotHash: hash,
            daemonKeyHue: daemonKeyHue,
            coordinateCount: densityMap.count,
            totalDensity: totalDensity,
            dominantHue: totalDensity > 0 ? daemonKeyHue : nil,
            markings: accumulator.allMarkings(),
            timestamp: ContinuousClock.now
        )
    }
}
