import Foundation
import CreatureSpine

/// Bridges a node's per-grammar `NodeReadiness` into the project's additive
/// colour law. This is the heart of the B3 rework: readiness is expressed as
/// **interleaved per-grammar colour tracks mixed with the existing
/// `AdditiveMixer`** — NOT a flat status enum.
///
/// The mixing MATH is `AdditiveMixer`, unchanged (energy-weighted circular mean;
/// same hues reinforce, DIFFERENT hues desaturate toward white; zero-energy
/// tracks accepted but carry no weight). This adapter only turns verdicts into
/// the `ColourTrack`s that mixer consumes, and turns the mixed `ColourTrack`
/// back into the `DecodedColour` the Atlas/CLI render with — exactly matching
/// `TrunkAtlas.colour`'s representation.
///
/// For each participating grammar we build one track:
///   - **hue** = `TrunkColour.hueForLanguage(language)` (its grammar identity).
///   - **energy** (saturation×value) encodes the verdict:
///       * `.holds`   → FULL energy — the standard `TrunkColour.forLanguage`
///                      saturation/value (~0.75 / 0.9). It participates in the
///                      "holds" mix.
///       * `.broken`  → ZERO energy — it falls OUT of the mix; the colour shifts
///                      toward the remaining grammars' chroma.
///       * `.unprobed`→ ZERO energy — present but weightless (the honest
///                      "unprobed", NOT a fake hold).
///
/// WHITE therefore EMERGES from multiple holding grammars (different hues, bright
/// → additive desaturation toward white) = "holds for all present grammars." A
/// single holding grammar → its pure hue. White is never special-cased; it
/// falls out of the mix.
public enum ReadinessMixer {

    /// The coordinate every readiness track is anchored at. The position is
    /// INCIDENTAL to the readiness mix — the mixer needs *a* coordinate to
    /// construct a track, and the origin is the neutral choice, so no spatial
    /// dependency leaks into trunk verdict logic beyond this one constant.
    static let trackOrigin = SpineCoordinate.origin

    /// A single marking stamped on readiness tracks — readiness is a byproduct
    /// signal, not a creature reaction, so the marking is nominal and only used
    /// by the mixer's dominant-marking bookkeeping (which we ignore).
    static let readinessMarking = CreatureMarking(name: "readiness", pattern: 0)

    /// Full-energy hold: reuse `TrunkColour.forLanguage`'s standard chroma so a
    /// holding grammar's readiness track is exactly its grammar-identity colour.
    static let holdSaturation: Float = 0.75
    static let holdValue: Float = 0.9

    /// Build the participating readiness tracks for a node — one `ColourTrack`
    /// per grammar in `readiness.verdicts`, at that grammar's hue, with energy
    /// per its verdict. Broken and unprobed grammars produce zero-energy tracks
    /// (present, weightless) so the mix reflects only the grammars that hold.
    public static func tracks(for readiness: NodeReadiness) -> [ColourTrack] {
        readiness.languages.map { language in
            let verdict = readiness.verdicts[language] ?? .unprobed
            let hue = TrunkColour.hueForLanguage(language)
            let (saturation, value): (Float, Float)
            switch verdict {
            case .holds:
                (saturation, value) = (holdSaturation, holdValue)
            case .broken, .unprobed:
                // Zero energy → falls out of the additive mix (no weight).
                (saturation, value) = (0, 0)
            }
            return ColourTrack(
                coordinate: trackOrigin,
                hue: hue,
                saturation: saturation,
                value: value,
                creatureMarking: readinessMarking
            )
        }
    }

    /// A node's single-glance readiness colour: the `AdditiveMixer.mix()` of its
    /// participating tracks, bridged to `ColourTrackEncoder.DecodedColour` for
    /// display (matching `TrunkAtlas.colour`).
    ///
    /// Returns `nil` only when the node participates in NO grammar at all
    /// (empty verdicts) OR every participating grammar is zero-energy (all
    /// broken/unprobed) — in both cases there is no holding chroma to show, and
    /// the caller renders it as the neutral "unprobed / no-signal" colour rather
    /// than any hue (never a false green/white).
    public static func mix(_ readiness: NodeReadiness) -> ColourTrackEncoder.DecodedColour? {
        let tracks = tracks(for: readiness)
        guard !tracks.isEmpty else { return nil }

        // If NO grammar holds, there is no chroma to emit — the mixer would fall
        // back to returning `tracks[0]` as-is (its zero-energy contract), which
        // for a zero-saturation track is a meaningless hue. Report "no signal"
        // explicitly instead so the render is honest.
        let anyHolds = readiness.verdicts.values.contains { $0.isHold }
        guard anyHolds else { return nil }

        var mixer = AdditiveMixer()
        for track in tracks { mixer.add(track) }
        guard let mixed = mixer.mix() else { return nil }

        return ColourTrackEncoder.DecodedColour(
            hue: mixed.hue,
            saturation: mixed.saturation,
            value: mixed.value,
            pattern: mixed.creatureMarking.pattern
        )
    }
}
