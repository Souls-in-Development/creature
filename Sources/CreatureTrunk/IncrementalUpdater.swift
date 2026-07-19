import Foundation

/// O(depth) incremental status updater.
///
/// When a leaf node's status changes, `IncrementalUpdater` recomputes rolled-up
/// statuses only for nodes that could be affected — ancestors in the structural
/// tree and reverse-edge dependents — rather than rebuilding the entire tree.
///
/// Propagation rules:
/// - **Structural:** a child's rolled-up change propagates to its parent (the
///   parent's rolled-up depends on its children's rolled-up statuses).
/// - **Edges:** a target's *own* status change propagates to sources that have
///   an edge to it (the source's rolled-up depends on the target's leaf status).
///
/// The algorithm uses a work-list (no visited set) so that nodes reached via
/// multiple paths are re-evaluated until convergence. Because `TrunkStatus` has
/// a finite severity lattice, convergence is guaranteed.
public struct IncrementalUpdater: Sendable {
    public let tree: TreeIndex
    public var rolledUpStatus: [String: TrunkStatus]
    public var leafStatus: [String: TrunkStatus]
    public let bridge: TrunkBridge?

    public init(
        tree: TreeIndex,
        rolledUpStatus: [String: TrunkStatus],
        leafStatus: [String: TrunkStatus],
        bridge: TrunkBridge? = nil
    ) {
        self.tree = tree
        self.rolledUpStatus = rolledUpStatus
        self.leafStatus = leafStatus
        self.bridge = bridge
    }

    /// Update one leaf status and propagate changes.
    ///
    /// - Parameters:
    ///   - nodeID: The node whose leaf status changed.
    ///   - newStatus: The new leaf status.
    /// - Returns: A dictionary of node IDs whose rolled-up status changed,
    ///   mapped to their new rolled-up value. The dictionary is empty if the
    ///   change had no effect on any ancestor or reverse-edge dependent.
    @discardableResult
    public mutating func update(nodeID: String, to newStatus: TrunkStatus) -> [String: TrunkStatus] {
        leafStatus[nodeID] = newStatus
        var changed: [String: TrunkStatus] = [:]
        var worklist: Set<String> = []

        // Only propagate if the node exists in the tree.
        if tree.contains(nodeID: nodeID) {
            worklist.insert(nodeID)
        }

        while let current = worklist.popFirst() {
            guard tree.contains(nodeID: current) else { continue }

            let oldRolledUp = rolledUpStatus[current] ?? .unknown
            let newRolledUp = computeRolledUp(for: current)

            guard oldRolledUp != newRolledUp else { continue }

            rolledUpStatus[current] = newRolledUp
            changed[current] = newRolledUp

            // Structural propagation: parent may depend on this child's rolled-up.
            if let parentID = tree.parentByNode[current], let parent = parentID {
                worklist.insert(parent)
            }

            // Reverse-edge propagation: sources that depend on this node's *own* status.
            if let bridge = bridge {
                for edge in bridge.edges(to: current) {
                    worklist.insert(edge.source)
                }
            }
        }

        return changed
    }

    /// Recompute the rolled-up status for a single node using the current
    /// cached values. This mirrors `RollUpEngine.compute()` but for one node.
    private func computeRolledUp(for nodeID: String) -> TrunkStatus {
        let own = leafStatus[nodeID] ?? .unknown
        let children = tree.childrenByParent[nodeID] ?? []
        var worst = own
        for childID in children {
            if let childRolledUp = rolledUpStatus[childID] {
                worst = TrunkStatus.worst(worst, childRolledUp)
            }
        }
        if let bridge = bridge {
            for edge in bridge.edges(from: nodeID) {
                let targetOwn = leafStatus[edge.target] ?? .unknown
                worst = TrunkStatus.worst(worst, targetOwn)
            }
        }
        return worst
    }
}
