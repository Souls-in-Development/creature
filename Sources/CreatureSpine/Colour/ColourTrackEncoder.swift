// SIMD4 and friends are Swift standard library types; the `simd` module itself
// is Apple-only and not actually needed here. Foundation supplies `sqrt`/`round`
// on every platform (they came in via `simd` on Apple, which is why this file
// had no explicit import before).
import Foundation
#if canImport(simd)
import simd
#endif

/// Encodes ColourTrack data to SIMD4<Float> for GPU texture storage.
/// Layout: R = hue/360, G = saturation, B = value, A = pattern/255.
/// Pure SIMD math — no Metal import required.
public enum ColourTrackEncoder {

    /// Encode a ColourTrack to SIMD4<Float>.
    public static func encode(_ track: ColourTrack) -> SIMD4<Float> {
        SIMD4<Float>(
            track.hue / 360.0,
            track.saturation,
            track.value,
            Float(track.creatureMarking.pattern) / 255.0
        )
    }

    /// Encode a DirtyEntry (aggregated trail data) to SIMD4<Float>.
    /// Uses density as saturation proxy, clamped value from density.
    public static func encodeEntry(_ entry: DirtyEntry) -> SIMD4<Float> {
        let hue = (entry.averageHue ?? 0.0) / 360.0
        let saturation = min(1.0, entry.density)
        let value = min(1.0, sqrt(entry.density))  // sqrt for perceptual scaling
        let pattern = Float(entry.dominantMarking?.pattern ?? 0) / 255.0

        return SIMD4<Float>(hue, saturation, value, pattern)
    }

    /// Decoded colour components from a SIMD4<Float> pixel.
    public struct DecodedColour: Sendable, Codable, Hashable {
        public let hue: Float         // 0-360
        public let saturation: Float  // 0-1
        public let value: Float       // 0-1
        public let pattern: UInt8     // 0-255

        public init(hue: Float, saturation: Float, value: Float, pattern: UInt8) {
            self.hue = hue
            self.saturation = saturation
            self.value = value
            self.pattern = pattern
        }
    }

    /// Decode SIMD4<Float> back to colour components.
    public static func decode(_ pixel: SIMD4<Float>) -> DecodedColour {
        DecodedColour(
            hue: pixel.x * 360.0,
            saturation: pixel.y,
            value: pixel.z,
            pattern: UInt8(clamping: Int(round(pixel.w * 255.0)))
        )
    }
}
