import Foundation

/// Bottom-up status roll-up engine.
///
/// Replaces the O(n²) `TrunkAtlas.status(rootedAt:)` scan with a single
/// O(n + e) bottom-up pass over a `TreeIndex`.
///
/// Algorithm:
/// 1. Process nodes deepest-first (post-order).
/// 2. For each node: `rolledUp = worst(ownStatus, children's rolledUp, edge targets' ownStatus)`.
/// 3. Result is cached in `rolledUpStatus: [String: TrunkStatus]`.
public struct RollUpEngine: Sendable {
    public let tree: TreeIndex
    public let leafStatus: [String: TrunkStatus]
    public let bridge: TrunkBridge?

    public init(tree: TreeIndex, leafStatus: [String: TrunkStatus], bridge: TrunkBridge? = nil) {
        self.tree = tree
        self.leafStatus = leafStatus
        self.bridge = bridge
    }

    /// Compute the rolled-up status for every node in the tree.
    ///
    /// - Returns: A dictionary mapping every node ID to its rolled-up status.
    ///   Nodes not present in the tree are omitted. Nodes with no explicit
    ///   leaf status default to `.unknown`.
    public func compute() -> [String: TrunkStatus] {
        var rolledUp: [String: TrunkStatus] = [:]

        // Bottom-up: deepest first
        for nodeID in tree.deepestFirst {
            let own = leafStatus[nodeID] ?? .unknown

            // Structural children rollup
            let children = tree.childrenByParent[nodeID] ?? []
            var worst = own
            for childID in children {
                if let childRolledUp = rolledUp[childID] {
                    worst = TrunkStatus.worst(worst, childRolledUp)
                }
            }

            // Edge propagation: direct edges only (v0)
            if let bridge = bridge {
                for edge in bridge.edges(from: nodeID) {
                    let targetOwn = leafStatus[edge.target] ?? .unknown
                    worst = TrunkStatus.worst(worst, targetOwn)
                }
            }

            rolledUp[nodeID] = worst
        }

        return rolledUp
    }
}
