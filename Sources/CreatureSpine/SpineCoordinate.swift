import Foundation

/// Where a creature sits in the spine's field.
///
/// A plain spherical position: two angles plus a non-negative depth. It exists so
/// creatures can have a location, a distance to each other, and trails through the
/// field (see `ColourTrack`, `TrailAccumulator`, `WaveInterference`). It carries no
/// meaning of its own — callers decide what a position signifies.
///
/// Note this is NOT the code-structure address space. Code is placed by
/// `TrunkCoordinate` (module → file → symbol), which is deliberately separate;
/// see its doc comment.
public struct SpineCoordinate: Equatable, Hashable, Codable, Sendable {
    public let ra: Double
    public let dec: Double
    public let alt: Int

    public init(ra: Double, dec: Double, alt: Int) {
        self.ra = ra.clamped(to: 0...360)
        self.dec = dec.clamped(to: -90...90)
        self.alt = max(0, alt)
    }

    public var stringKey: String { "\(ra),\(dec),\(alt)" }

    /// Angular distance to another coordinate (ignores ALT).
    public func angularDistance(to other: SpineCoordinate) -> Double {
        let dRA = (ra - other.ra) * Double.pi / 180
        let dDEC = (dec - other.dec) * Double.pi / 180
        let a = sin(dDEC / 2) * sin(dDEC / 2) +
                cos(dec * .pi / 180) * cos(other.dec * .pi / 180) *
                sin(dRA / 2) * sin(dRA / 2)
        return 2 * atan2(sqrt(a), sqrt(1 - a)) * 180 / Double.pi
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Origin

extension SpineCoordinate {
    /// The origin of the field. Creatures with no assigned position start here.
    public static let origin = SpineCoordinate(ra: 0, dec: 0, alt: 0)
}
