import Foundation

/// A connection (edge) between two nodes in the trunk graph. Bridges turn the
/// structural tree into a dependency graph: "who calls whom," "who references
/// whom," etc.
///
/// Direction: `source` → `target` means the source *depends on* the target
/// (e.g., source calls target, source references target). If target is red,
/// source is impacted — propagation flows backward along the edge.
public struct TrunkEdge: Hashable, Sendable, Codable {
    public let source: String  // node id of the dependent / caller
    public let target: String  // node id of the dependency / callee
    public let kind: TrunkEdgeKind

    public init(source: String, target: String, kind: TrunkEdgeKind) {
        self.source = source
        self.target = target
        self.kind = kind
    }
}

/// Kind of dependency represented by a `TrunkEdge`.
public enum TrunkEdgeKind: String, Hashable, Sendable, Codable {
    /// A function or method call: `source` calls `target`.
    case call
    /// A symbol reference (e.g., reading a property, using a constant).
    case reference
    /// A type-level dependency (e.g., inheritance, conformance, type alias).
    case typeDependency
}

/// An edge whose target has not yet been resolved to a concrete node id.
/// Language tentacles produce these during indexing; the target is identified
/// by `truthKey` (the Channel-0 hash of the called symbol's skeleton). Once the
/// full trunk is assembled, `TrunkBridge.resolve(unresolved:against:)` maps
/// truthKeys to concrete node ids via `CodeTrunk.nodesSharing(truthKey:)` —
/// which naturally handles cross-language linking (a Swift call to `add/2` and
/// a Python call to `add/2` both resolve to the same trunk node).
public struct UnresolvedEdge: Sendable, Codable {
    public let source: String
    public let targetTruthKey: String
    public let kind: TrunkEdgeKind

    public init(source: String, targetTruthKey: String, kind: TrunkEdgeKind) {
        self.source = source
        self.targetTruthKey = targetTruthKey
        self.kind = kind
    }
}

/// The Bridge layer: edges between trunk nodes that turn the tree into a graph.
///
/// v0 scope: call edges extracted from function bodies by language tentacles,
/// resolved against the trunk using shared truthKeys. Edge propagation in Atlas
/// is direct (one hop) — transitive propagation is a future enhancement.
///
/// v0 honesty: call resolution is purely syntactic (name + arity). It does not
/// attempt scope-aware symbol resolution, overload disambiguation, or module
/// imports. Multiple nodes may share the same truthKey; an unresolved edge
/// resolves to *all* of them (conservative over-approximation, which is the
/// safe direction for error propagation).
public struct TrunkBridge: Sendable, Codable, Equatable {
    public private(set) var edges: [TrunkEdge]

    public init(edges: [TrunkEdge] = []) {
        self.edges = edges
    }

    public mutating func add(_ edge: TrunkEdge) {
        edges.append(edge)
    }

    /// All edges where `source` is the given node id.
    public func edges(from sourceID: String) -> [TrunkEdge] {
        edges.filter { $0.source == sourceID }
    }

    /// All edges where `target` is the given node id.
    public func edges(to targetID: String) -> [TrunkEdge] {
        edges.filter { $0.target == targetID }
    }

    /// Target node ids of all edges originating from `sourceID`.
    public func targets(of sourceID: String) -> [String] {
        edges(from: sourceID).map { $0.target }
    }

    /// Source node ids of all edges terminating at `targetID`.
    public func sources(of targetID: String) -> [String] {
        edges(to: targetID).map { $0.source }
    }

    /// Resolve a collection of `UnresolvedEdge`s against a `CodeTrunk`, producing
    /// a `TrunkBridge` with concrete node-to-node edges.
    ///
    /// Each unresolved edge is mapped via `CodeTrunk.nodesSharing(truthKey:)`.
    /// If multiple nodes share the same truthKey, one concrete edge is produced
    /// per target node — conservative over-approximation.
    public static func resolve(unresolved: [UnresolvedEdge], against trunk: CodeTrunk) -> TrunkBridge {
        var bridge = TrunkBridge()
        for edge in unresolved {
            let targets = trunk.nodesSharing(truthKey: edge.targetTruthKey)
            for target in targets {
                bridge.add(TrunkEdge(source: edge.source, target: target.id, kind: edge.kind))
            }
        }
        return bridge
    }
}
