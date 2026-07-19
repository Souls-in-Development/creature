import Foundation

/// The trunk: a collection of `TrunkNode`s addressable by id, by structural
/// path, and — the operation that makes the trunk useful — by shared
/// Channel-0 truth. Nodes whose Channel-0 skeleton hashes to the same
/// `truthKey` are asserted structurally equivalent, regardless of language,
/// file, or OS. That is the mechanism a flat per-language index cannot
/// provide (see `docs/plans/2026-07-05-creature-cursor-competitor-architecture.md`
/// section 3: "A Swift function and a Python function that do the same
/// thing land on the same Rosetta coordinate").
public struct CodeTrunk: Sendable, Codable {
    public private(set) var nodes: [TrunkNode]

    public init(nodes: [TrunkNode] = []) {
        self.nodes = nodes
    }

    /// Add a node to the trunk.
    public mutating func add(_ node: TrunkNode) {
        nodes.append(node)
    }

    /// Look up a node by id.
    public func node(id: String) -> TrunkNode? {
        nodes.first { $0.id == id }
    }

    /// Look up nodes by exact structural path.
    public func nodes(path: [String]) -> [TrunkNode] {
        nodes.filter { $0.coordinate.path == path }
    }

    /// Look up nodes by dotted path key (see `TrunkCoordinate.pathKey`).
    public func nodes(pathKey: String) -> [TrunkNode] {
        nodes.filter { $0.coordinate.pathKey == pathKey }
    }

    /// Cross-language/OS equivalence: all nodes whose Channel-0 truth
    /// (`TrunkCoordinate.truthKey`) matches the given key. This is the trunk's
    /// key lookup — it is how a Swift implementation and a Python
    /// implementation of "the same" function are found to be the same thing.
    ///
    /// v0 honesty: whether two genuinely-equivalent implementations actually
    /// share a `truthKey` depends entirely on how good the Channel-0
    /// normalizer is (see `CodeIngester`). v0's normalizer is intentionally
    /// simple (declaration shape only) and does NOT attempt full semantic
    /// equivalence — so this method's *mechanism* is real, but it will only
    /// link nodes whose normalized skeletons happen to match today.
    public func nodesSharing(truthKey: String) -> [TrunkNode] {
        nodes.filter { $0.coordinate.truthKey == truthKey }
    }

    /// Build a `TreeIndex` from this trunk's nodes.
    public func buildTreeIndex() -> TreeIndex {
        TreeIndex.from(nodes: nodes)
    }
}
