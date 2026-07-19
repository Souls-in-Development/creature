import Foundation
import CreatureSpine

/// Atlas: a status overlay over a `CodeTrunk`, built **once at the trunk
/// level** so every language tentacle feeds the same tree (see
/// `docs/plans/2026-07-05-creature-cursor-competitor-architecture.md` §4,
/// "Atlas completion tree"). `TrunkAtlas` itself knows nothing about any
/// particular language — it only knows nodes, coordinates, and statuses.
///
/// The overlay answers one question at every level of the tree: "is
/// everything under here OK?" A container node (a module, a type) is
/// `.green` only if it and everything nested beneath it is green — a single
/// red leaf turns every one of its ancestors red too. That's the roll-up.
///
/// HONEST SCOPE (v0): see `TrunkStatus`'s doc comment. This type's
/// *mechanism* — roll-up by structural-path descendance + edge propagation,
/// worst-of-set aggregation, overall verdict — is the universal, permanent
/// shape. What v0 actually *feeds* it (syntax-validity-only leaf statuses from
/// `SwiftIndexer.indexWithStatus`) is narrow and will be superseded by
/// richer per-node signals (type-checking, full compile-readiness) without
/// needing to change this type.
public struct TrunkAtlas: Sendable {
    /// The trunk this Atlas overlays.
    public let trunk: CodeTrunk

    /// Each node's *own* status (not rolled up), keyed by `TrunkNode.id`. A
    /// node absent from this map defaults to `.unknown` (see `ownStatus(for:)`).
    ///
    /// IMPORTANT with real compile-readiness (B3): when a probe ran, callers
    /// build this map from `DiagnosticReducer.reduce`, which sets an EXPLICIT
    /// status for every node — including `.unknown` for nodes in unprobed
    /// files. Rely on that explicitness rather than the absent-defaults-to-
    /// green fallback, since for an unprobed node "absent" would wrongly read
    /// as green (the exact false-green B3 exists to kill).
    public let leafStatus: [String: TrunkStatus]

    /// Optional dependency graph. When present, Atlas red-propagation follows
    /// edges: a node is red if any node it depends on (edge target) is red.
    /// v0: direct edges only (one hop). Transitive propagation is a future
    /// enhancement.
    public let bridge: TrunkBridge?

    /// Cached rolled-up status for every node, computed once at init time
    /// via `RollUpEngine` — replaces the O(n²) per-query scan with O(1)
    /// lookups.
    private let rolledUpStatus: [String: TrunkStatus]

    /// The worst rolled-up status across every node in the trunk — the
    /// single-glance "is the whole codebase green" verdict.
    public let overall: TrunkStatus

    public init(trunk: CodeTrunk, leafStatus: [String: TrunkStatus], bridge: TrunkBridge? = nil) {
        self.trunk = trunk
        self.leafStatus = leafStatus
        self.bridge = bridge
        let tree = TreeIndex.from(nodes: trunk.nodes)
        let engine = RollUpEngine(tree: tree, leafStatus: leafStatus, bridge: bridge)
        let rolledUp = engine.compute()
        self.rolledUpStatus = rolledUp
        self.overall = TrunkStatus.worst(of: tree.rootIDs.map { rolledUp[$0] ?? .unknown })
    }

    /// A node's own status, before roll-up. `.unknown` when the node has no entry
    /// in `leafStatus` — **absence is not evidence of health.** Callers must supply
    /// an explicit status for every node; `DiagnosticReducer.reduce` does exactly
    /// that. Defaulting absence to `.green` was the ambient false-green.
    public func ownStatus(for nodeID: String) -> TrunkStatus {
        leafStatus[nodeID] ?? .unknown
    }

    /// The rolled-up status of a node: the worst of its own status, every
    /// descendant's own status, and (when a bridge is present) the own status
    /// of every node this node depends on via an edge. A descendant is any node
    /// whose `coordinate.path` has this node's `coordinate.path` as a strict
    /// prefix (a longer path that starts with all of this node's path
    /// segments, in order) — i.e. anything structurally nested beneath it,
    /// regardless of language or which tentacle produced it.
    ///
    /// Edge propagation: if this node has an edge to another node, and that
    /// target node is red, this node is also considered red — "change a
    /// signature and every dependent node reddens." Direction is backward:
    /// `source` depends on `target`, so `target` redness flows to `source`.
    /// v0: direct edges only.
    ///
    /// Returns `.unknown` if `nodeID` isn't found in the trunk at all (a node
    /// we do not have cannot be certified. Not green).
    public func status(for nodeID: String) -> TrunkStatus {
        guard trunk.node(id: nodeID) != nil else { return .unknown }
        return rolledUpStatus[nodeID] ?? .unknown
    }

    /// Roll-up computed directly from a `TrunkNode`, for callers that already
    /// have the node in hand (e.g. printing the whole tree without an id
    /// round-trip through `trunk.node(id:)` per node).
    public func status(rootedAt node: TrunkNode) -> TrunkStatus {
        rolledUpStatus[node.id] ?? .unknown
    }

    /// Atlas status colour for a `TrunkStatus` — distinct from the
    /// per-language chroma used on `TrunkChannel` (see `TrunkColour`). This
    /// is a fixed, small traffic-light mapping: green/amber/red at full
    /// saturation and value so it reads clearly regardless of the language
    /// chroma sitting alongside it, plus a distinct **grey** for `unknown`
    /// (low saturation, mid value) so "not checked" is visibly neither health
    /// nor breakage — see `TrunkStatus`.
    public static func colour(for status: TrunkStatus) -> ColourTrackEncoder.DecodedColour {
        switch status {
        case .green:
            return ColourTrackEncoder.DecodedColour(hue: 120, saturation: 0.8, value: 0.85, pattern: 0)
        case .yellow:
            return ColourTrackEncoder.DecodedColour(hue: 45, saturation: 0.9, value: 0.95, pattern: 0)
        case .red:
            return ColourTrackEncoder.DecodedColour(hue: 0, saturation: 0.85, value: 0.9, pattern: 0)
        case .unknown:
            // Grey: low saturation, mid value — reads as "no signal / not
            // checked," clearly apart from the three saturated verdicts.
            return ColourTrackEncoder.DecodedColour(hue: 0, saturation: 0.0, value: 0.5, pattern: 0)
        }
    }

    /// Instance-method convenience for `Self.colour(for:)`.
    public func colour(for status: TrunkStatus) -> ColourTrackEncoder.DecodedColour {
        Self.colour(for: status)
    }
}
