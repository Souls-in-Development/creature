import Foundation

/// A code-native structural coordinate — where a unit of code sits in the trunk.
///
/// This is deliberately its OWN address space, separate from `SpineCoordinate`
/// (the spine's spatial field). Code has its own topology: it lives in a
/// module → file → symbol hierarchy, not in a sphere. Keeping the two apart means
/// neither has to distort to fit the other.
///
/// `truthKey` is the stable identity of this node's Channel-0 truth (see
/// `TrunkNode`) — a hash of the language-agnostic structural skeleton, not of
/// this coordinate. Two nodes at different paths (different files, different
/// languages) can carry the same `truthKey` if their Channel-0 skeletons
/// match; that equivalence is what `CodeTrunk.nodesSharing(truthKey:)` finds.
///
/// - Future hook: `externalLink` is a reserved, unused slot for associating a
///   trunk coordinate with an identifier from some other system. v0 neither
///   populates nor reads it — it exists so a later pass can add that association
///   without migrating `TrunkCoordinate`'s shape.
public struct TrunkCoordinate: Hashable, Sendable, Codable {
    /// Structural path from outermost container to the symbol itself,
    /// e.g. ["MyModule", "MyType", "myFunction"].
    public let path: [String]

    /// Nesting depth (`path.count`, kept explicit so callers don't recompute it
    /// and so it survives independently if `path` semantics change later).
    public let depth: Int

    /// Structural kind at this coordinate: "module", "type", "function",
    /// "property", etc. v0 keeps this a free-form string (language adapters
    /// decide their own vocabulary); a shared enum can replace it once more
    /// than one language adapter exists and the vocabulary stabilizes.
    public let kind: String

    /// Stable identity of this node's Channel-0 (language-agnostic) truth.
    /// Two `TrunkNode`s with equal `truthKey` are asserted structurally
    /// equivalent regardless of language or path. See `CodeTrunk.nodesSharing`.
    public let truthKey: String

    /// Reserved, unused in v0. See the type doc comment.
    public let externalLink: String?

    public init(
        path: [String],
        kind: String,
        truthKey: String,
        externalLink: String? = nil
    ) {
        self.path = path
        self.depth = path.count
        self.kind = kind
        self.truthKey = truthKey
        self.externalLink = externalLink
    }

    /// Dotted rendering of `path`, e.g. "MyModule.MyType.myFunction".
    public var pathKey: String { path.joined(separator: ".") }
}
