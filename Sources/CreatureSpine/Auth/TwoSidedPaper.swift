/// Visual authentication layer for colour tracks.
///
/// Authenticated = full canonical colours (owner's wallpaper view).
/// Unauthenticated = tinted/desaturated with anonymized creature marking
/// (federation view, public display).
///
/// Hue is always preserved — the pattern remains recognizable through tint.
/// This is multimodal auth: the user recognizes their AI's "look" even
/// when desaturated. NOT keychain-based.
public enum TwoSidedPaper {

    /// Authentication state.
    public enum AuthState: Sendable {
        /// Full canonical colours — owner's view.
        case authenticated
        /// Tinted/desaturated with anonymized marking — public view.
        case unauthenticated
    }

    /// Tint multiplier for unauthenticated saturation (30%).
    private static let tintMultiplier: Float = 0.3

    /// Anonymous marking used for unauthenticated views.
    private static let anonymousMarking = CreatureMarking(name: "unknown", pattern: 0)

    /// Maximum hue difference (degrees) for pattern recognition verification.
    private static let hueToleranceDegrees: Float = 5.0

    /// Render a ColourTrack for the given auth state.
    public static func view(for track: ColourTrack, auth: AuthState) -> ColourTrack {
        switch auth {
        case .authenticated:
            return track
        case .unauthenticated:
            return applyTint(track)
        }
    }

    /// Batch render multiple tracks for the given auth state.
    public static func batchView(for tracks: [ColourTrack], auth: AuthState) -> [ColourTrack] {
        switch auth {
        case .authenticated:
            return tracks
        case .unauthenticated:
            return tracks.map { applyTint($0) }
        }
    }

    /// Verify that a tinted track's hue matches the canonical track's hue.
    /// Returns true if the hue difference is within tolerance (5 degrees).
    /// This models multimodal pattern recognition — the user can still
    /// identify the pattern through the tint because hue is preserved.
    public static func verifyPatternRecognition(canonical: ColourTrack, tinted: ColourTrack) -> Bool {
        // Circular hue distance
        let diff = abs(canonical.hue - tinted.hue)
        let circularDiff = min(diff, 360.0 - diff)
        return circularDiff < hueToleranceDegrees
    }

    // MARK: - Private

    private static func applyTint(_ track: ColourTrack) -> ColourTrack {
        ColourTrack(
            coordinate: track.coordinate,
            hue: track.hue,                              // Preserve hue
            saturation: track.saturation * tintMultiplier, // Desaturate to 30%
            value: track.value,                           // Preserve energy
            creatureMarking: anonymousMarking             // Anonymize identity
        )
    }
}
