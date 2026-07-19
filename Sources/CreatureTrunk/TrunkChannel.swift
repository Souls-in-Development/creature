import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
// Apple's own cross-platform implementation of the same API (swift-crypto).
// Only SHA-256 is used, and it is source-identical on both.
import Crypto
#endif
import CreatureSpine

/// One channel of a `TrunkNode`: a single language rendering (or, at index 0,
/// the language-agnostic structural truth) of one unit of code.
///
/// Colour follows the project's colour law (white↔black = truth axis, chroma
/// = perspective/identity — see `project_colour_identity_axis`):
/// - Channel 0 is always **white** — it is the invariant, the truth every
///   language view projects from. White has no chroma to disagree about.
/// - Channels 1+ each get a **distinct chroma** derived deterministically
///   from their language name, so "swift" is always the same hue and always
///   distinct from "python". This reuses `ColourTrackEncoder`'s
///   hue/saturation/value colour representation (`DecodedColour`) rather than
///   inventing a new colour type.
public struct TrunkChannel: Hashable, Sendable, Codable {
    /// Channel index (0 = Channel-0 structural truth).
    public let index: Int
    /// Language name ("rosetta" for Channel 0, "swift", "python", etc. for 1+).
    public let language: String
    /// Colour of this channel — white for Channel 0, a distinct chroma per
    /// language for channels 1+. Reuses `ColourTrackEncoder.DecodedColour`.
    public let colour: ColourTrackEncoder.DecodedColour
    /// Raw content of this channel — source text for language channels,
    /// normalized skeleton text for Channel 0.
    public let content: String

    public init(index: Int, language: String, colour: ColourTrackEncoder.DecodedColour, content: String) {
        self.index = index
        self.language = language
        self.colour = colour
        self.content = content
    }

    /// Build a channel with the colour derived automatically per the colour
    /// law: Channel 0 → white, Channel 1+ → chroma keyed on `language`.
    public init(index: Int, language: String, content: String) {
        self.init(
            index: index,
            language: language,
            colour: index == 0 ? TrunkColour.white : TrunkColour.forLanguage(language),
            content: content
        )
    }
}

/// Deterministic colour derivation for trunk channels, per the colour law:
/// white = truth/invariant, chroma = perspective/identity.
public enum TrunkColour {
    /// Channel 0's colour: white — full desaturation, full value. The
    /// language-agnostic structural truth carries no chroma because it is
    /// not any one perspective.
    public static let white = ColourTrackEncoder.DecodedColour(hue: 0, saturation: 0, value: 1, pattern: 0)

    /// A distinct, stable chroma for a language name. Same language name
    /// always yields the same hue; different names are spread around the
    /// hue wheel via a stable hash so they read as visually distinct.
    public static func forLanguage(_ language: String) -> ColourTrackEncoder.DecodedColour {
        let hue = hueForLanguage(language)
        return ColourTrackEncoder.DecodedColour(hue: hue, saturation: 0.75, value: 0.9, pattern: 0)
    }

    /// Hash the language name (SHA-256) and map the first 4 bytes to a hue
    /// in [0, 360). Deterministic across runs/platforms (CryptoKit, not
    /// `Hashable.hashValue` which is randomized per-process).
    public static func hueForLanguage(_ language: String) -> Float {
        let digest = SHA256.hash(data: Data(language.lowercased().utf8))
        let bytes = Array(digest)
        let word = (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
        return Float(word % 360)
    }
}
