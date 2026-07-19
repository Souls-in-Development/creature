import Foundation

/// A single unit of code in the Rosetta trunk: one structural coordinate
/// carrying a stack of interleaved channels. Channel 0 is always the
/// language-agnostic structural truth (white); channels 1+ are source
/// renderings, one per language, each in its own distinct chroma.
///
/// This is the `InterleavedDocument` shape (see
/// `CreatureSpine/Identity/InterleavedDocument.swift`) grown into a
/// code-native node: same "Channel 0 = truth, channels 1+ = views" contract,
/// but keyed by `TrunkCoordinate` instead of a constellation/human/daemon
/// bond, and carrying trunk-flavoured colour instead of a bond hash.
public struct TrunkNode: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let coordinate: TrunkCoordinate
    public let channels: [TrunkChannel]

    /// Where this node lives in real source (file + inclusive line range), when
    /// a tentacle captured it at index time. Optional so synthetic/test nodes
    /// (and every call site that predates B3) still work — a node with no span
    /// simply can't be the target of span-based diagnostic attribution (see
    /// `DiagnosticReducer`). Codable: absent decodes as `nil`, so older
    /// persisted nodes round-trip unchanged.
    public let span: SourceSpan?

    public init(
        id: String,
        coordinate: TrunkCoordinate,
        channels: [TrunkChannel],
        span: SourceSpan? = nil
    ) {
        self.id = id
        self.coordinate = coordinate
        self.channels = channels.sorted { $0.index < $1.index }
        self.span = span
    }

    /// Channel 0 — the language-agnostic structural truth. Absent only if
    /// the node was constructed without one (not produced by `ingest`).
    public var truthChannel: TrunkChannel? { channel(at: 0) }

    /// Look up a channel by index.
    public func channel(at index: Int) -> TrunkChannel? {
        channels.first { $0.index == index }
    }

    /// Look up a channel by language name (case-insensitive).
    public func channel(language: String) -> TrunkChannel? {
        channels.first { $0.language.caseInsensitiveCompare(language) == .orderedSame }
    }
}
