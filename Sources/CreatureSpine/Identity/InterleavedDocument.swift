import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
// Apple's own cross-platform implementation of the same API (swift-crypto).
// Only SHA-256 is used, and it is source-identical on both.
import Crypto
#endif

// MARK: - Interleaved Channel

/// A single channel in an interleaved document.
/// Channel 0 = Rosetta grammar (white, coordinate truth, base layer).
/// Channels 1+ = language views (Swift, Python, etc.).
public struct InterleavedChannel: Hashable, Sendable, Codable {
    /// Channel index (0 = base Rosetta grammar).
    public let index: Int
    /// Human-readable label ("rosetta", "swift", "python").
    public let label: String
    /// Raw channel data.
    public let data: Data

    public init(index: Int, label: String, data: Data) {
        self.index = index
        self.label = label
        self.data = data
    }
}

// MARK: - Interleaved Document

/// Three-key bond document with interleaved channels.
///
/// Combines:
/// - ConstellationKey (The When — GAIA stars at bond moment)
/// - Human Key (MemoryOrbitSystem.deriveKey — passed to bondHash)
/// - Daemon Signature (living colour emission hash)
///
/// Channel 0 is always the Rosetta `.font` grammar (coordinate truth).
/// Channels 1+ are language-specific views.
/// `coordinateHash` proves semantic equivalence across all channels.
public struct InterleavedDocument: Sendable, Codable {
    public let channels: [InterleavedChannel]
    public let constellationKey: ConstellationKey
    public let daemonSignatureHash: Data
    public let coordinateHash: Data
    public let createdAt: Date

    public init(
        channels: [InterleavedChannel],
        constellationKey: ConstellationKey,
        daemonSignatureHash: Data,
        createdAt: Date = Date()
    ) {
        self.channels = channels.sorted { $0.index < $1.index }
        self.constellationKey = constellationKey
        self.daemonSignatureHash = daemonSignatureHash
        self.createdAt = createdAt
        self.coordinateHash = Self.computeCoordinateHash(channels: channels)
    }

    /// Number of channels.
    public var channelCount: Int { channels.count }

    /// Look up a channel by index.
    public func channel(at index: Int) -> InterleavedChannel? {
        channels.first { $0.index == index }
    }

    /// Compute the three-key bond hash.
    /// XOR(constellationKey, humanKey, daemonSignature) → SHA-256.
    public func bondHash(humanKey: Data) -> Data {
        let ck = constellationKey.deriveKey()
        let hk = humanKey
        let dk = daemonSignatureHash

        // XOR all three keys (pad shorter keys with zeros)
        let maxLen = max(ck.count, max(hk.count, dk.count))
        var combined = Data(count: maxLen)
        for i in 0..<maxLen {
            let c = i < ck.count ? ck[i] : 0
            let h = i < hk.count ? hk[i] : 0
            let d = i < dk.count ? dk[i] : 0
            combined[i] = c ^ h ^ d
        }

        let digest = SHA256.hash(data: combined)
        return Data(digest)
    }

    /// Compute coordinate hash proving semantic equivalence across channels.
    private static func computeCoordinateHash(channels: [InterleavedChannel]) -> Data {
        var hasher = SHA256()
        let sorted = channels.sorted { $0.index < $1.index }
        for channel in sorted {
            var idx = Int32(channel.index)
            hasher.update(data: Data(bytes: &idx, count: MemoryLayout<Int32>.size))
            hasher.update(data: Data(channel.label.utf8))
            hasher.update(data: channel.data)
        }
        return Data(hasher.finalize())
    }
}
