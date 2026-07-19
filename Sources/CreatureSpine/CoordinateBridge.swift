import Foundation

/// Bridges between CognitiveCoordinate (alt: Double) used in apps/
/// and SpineCoordinate (alt: Int) used in the spine.
///
/// CognitiveCoordinate is defined in apps/RosettaAI/Cognitive/Types/P12Types.swift.
/// We can't import it (different module), so the bridge uses raw components.
public enum CoordinateBridge {
    /// Convert from CognitiveCoordinate's (ra, dec, alt: Double) to SpineCoordinate.
    /// ALT is rounded to nearest Int. Values are clamped to valid ranges.
    public static func fromCognitive(ra: Double, dec: Double, alt: Double) -> SpineCoordinate {
        SpineCoordinate(ra: ra, dec: dec, alt: Int(alt.rounded()))
    }

    /// Convert from SpineCoordinate to (ra, dec, alt: Double) tuple
    /// for use with CognitiveCoordinate.
    public static func toCognitive(_ coord: SpineCoordinate) -> (ra: Double, dec: Double, alt: Double) {
        (ra: coord.ra, dec: coord.dec, alt: Double(coord.alt))
    }
}
