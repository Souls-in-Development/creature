import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
// Apple's own cross-platform implementation of the same API (swift-crypto).
// Only SHA-256 is used, and it is source-identical on both.
import Crypto
#endif

/// A star from the GAIA catalog with astrometric parameters.
public struct GAIAStar: Hashable, Sendable, Codable {
    /// Unique GAIA DR3 source identifier.
    public let sourceID: String
    /// Right ascension (degrees).
    public let ra: Double
    /// Declination (degrees).
    public let dec: Double
    /// Parallax (milliarcseconds).
    public let parallax: Double
    /// Proper motion in RA (mas/year).
    public let properMotionRA: Double
    /// Proper motion in DEC (mas/year).
    public let properMotionDEC: Double

    public init(sourceID: String, ra: Double, dec: Double,
                parallax: Double, properMotionRA: Double, properMotionDEC: Double) {
        self.sourceID = sourceID
        self.ra = ra
        self.dec = dec
        self.parallax = parallax
        self.properMotionRA = properMotionRA
        self.properMotionDEC = properMotionDEC
    }
}

/// Captures which GAIA stars were visible at bond formation moment.
/// Identity is tied to the user's downloaded star dataset — uncopyable
/// because that exact combination of stars + moment is gone forever.
public struct ConstellationKey: Hashable, Sendable, Codable {
    /// The moment the bond was formed.
    public let bondMoment: Date
    /// Stars visible in the user's downloaded region at bond time.
    public let visibleStars: [GAIAStar]
    /// SHA-256 hash of sorted star source IDs — deterministic, order-independent.
    public let regionHash: String

    /// Number of stars in this constellation snapshot.
    public var starCount: Int { visibleStars.count }

    /// Capture a constellation key from the user's downloaded star dataset.
    /// Star IDs are sorted before hashing for order independence.
    public static func capture(
        visibleStars: [GAIAStar],
        at date: Date = Date()
    ) -> ConstellationKey {
        let sortedIDs = visibleStars.map(\.sourceID).sorted()
        let joined = sortedIDs.joined(separator: "|")
        let hashDigest = SHA256.hash(data: Data(joined.utf8))
        let hashString = hashDigest.map { String(format: "%02x", $0) }.joined()

        return ConstellationKey(
            bondMoment: date,
            visibleStars: visibleStars,
            regionHash: hashString
        )
    }

    /// Derive a 32-byte key from this constellation snapshot.
    /// Combines region hash with bond moment for temporal uniqueness.
    public func deriveKey() -> Data {
        var hasher = SHA256()
        hasher.update(data: Data(regionHash.utf8))
        withUnsafeBytes(of: bondMoment.timeIntervalSince1970) { hasher.update(bufferPointer: $0) }
        return Data(hasher.finalize())
    }
}
