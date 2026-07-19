import Foundation

/// An O(n) structural index over a flat `[TrunkNode]` list.
///
/// `TreeIndex` replaces linear-scan lookups with path-keyed hash maps so that
/// ancestor/descendant queries — the hot path for Atlas roll-up — are fast.
/// It is built once from a node list (`TreeIndex.from(nodes:)`) and is
/// immutable thereafter.
///
/// Structural parent/child is defined by `TrunkCoordinate.path`: a node is a
/// child of another if its path is exactly one segment longer and shares the
/// same prefix.  Nodes at the same `pathKey` are grouped together (the index
/// does not enforce uniqueness).
///
/// The index provides **two views** of the same tree:
/// 1. A **node-ID view** (`childrenByParent`, `parentByNode`, `nodesByDepth`,
///    `rootIDs`, `deepestFirst`) optimised for RollUpEngine, which works with
///    `leafStatus` keyed by node ID.
/// 2. A **path-key view** (`pathKeyToNodeIDs`, `parentToChildren`, etc.) as
///    required by the completion-tree plan for structural queries.
public struct TreeIndex: Sendable, Codable, Equatable {
    // MARK: - Node-ID view (RollUpEngine interface)

    /// Map from parent node ID to its direct structural children's node IDs.
    public let childrenByParent: [String: [String]]

    /// Map from node depth to the node IDs at that depth.
    public let nodesByDepth: [Int: [String]]

    /// Map from node ID to its parent node ID. `nil` means the node is a root.
    public let parentByNode: [String: String?]

    /// All node IDs whose parent is `nil` (roots).
    public let rootIDs: [String]

    /// All node IDs in the index, sorted by descending depth (deepest first).
    /// Useful for bottom-up traversals.
    public let deepestFirst: [String]

    // MARK: - Path-key view (structural query interface)

    /// Map from a pathKey to the node IDs that live at that path.
    public let pathKeyToNodeIDs: [String: [String]]

    /// Map from a parent pathKey to the pathKeys of its immediate children.
    public let parentToChildren: [String: [String]]

    /// Map from node ID back to its pathKey.
    public let nodeIDToPathKey: [String: String]

    /// Map from node ID back to its own depth.
    public let nodeIDToDepth: [String: Int]

    /// All pathKeys that have no parent in the index (roots).
    public let rootPathKeys: [String]

    /// The maximum depth found in the indexed nodes (`0` when empty).
    public let maxDepth: Int

    /// Total number of indexed nodes.
    public let count: Int

    // MARK: - Initialiser

    public init(
        childrenByParent: [String: [String]],
        nodesByDepth: [Int: [String]],
        parentByNode: [String: String?],
        rootIDs: [String],
        deepestFirst: [String],
        pathKeyToNodeIDs: [String: [String]],
        parentToChildren: [String: [String]],
        nodeIDToPathKey: [String: String],
        nodeIDToDepth: [String: Int],
        rootPathKeys: [String],
        maxDepth: Int,
        count: Int
    ) {
        self.childrenByParent = childrenByParent
        self.nodesByDepth = nodesByDepth
        self.parentByNode = parentByNode
        self.rootIDs = rootIDs
        self.deepestFirst = deepestFirst
        self.pathKeyToNodeIDs = pathKeyToNodeIDs
        self.parentToChildren = parentToChildren
        self.nodeIDToPathKey = nodeIDToPathKey
        self.nodeIDToDepth = nodeIDToDepth
        self.rootPathKeys = rootPathKeys
        self.maxDepth = maxDepth
        self.count = count
    }

    // MARK: - Builder

    /// Build a `TreeIndex` from a flat list of nodes in a single O(n) pass.
    public static func from(nodes: [TrunkNode]) -> TreeIndex {
        // --- Path-key view accumulators ---
        var pathKeyToNodeIDs: [String: [String]] = [:]
        var nodeIDToPathKey: [String: String] = [:]
        var nodesByDepth: [Int: [String]] = [:]
        var nodeIDToDepth: [String: Int] = [:]
        var allPathKeys: Set<String> = Set()

        // First pass: collect node data and all path prefixes
        for node in nodes {
            let pk = node.coordinate.pathKey
            pathKeyToNodeIDs[pk, default: []].append(node.id)
            nodeIDToPathKey[node.id] = pk
            nodesByDepth[node.coordinate.depth, default: []].append(node.id)
            nodeIDToDepth[node.id] = node.coordinate.depth
            allPathKeys.insert(pk)

            // Insert all prefixes so structural queries work for sparse trees
            let parts = pk.split(separator: ".", omittingEmptySubsequences: false)
            for i in 1..<parts.count {
                let prefix = parts.prefix(i).joined(separator: ".")
                allPathKeys.insert(prefix)
            }
        }

        // Build parent -> children map for ALL path keys
        var parentToChildren: [String: [String]] = [:]
        for pk in allPathKeys {
            let parts = pk.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count > 1 else { continue }
            let parent = parts.dropLast().joined(separator: ".")
            parentToChildren[parent, default: []].append(pk)
        }

        // Sort children arrays deterministically
        for (key, value) in parentToChildren {
            parentToChildren[key] = value.sorted()
        }

        // --- Node-ID view accumulators ---
        var childrenByParent: [String: [String]] = [:]
        var parentByNode: [String: String?] = [:]

        for node in nodes {
            let pk = node.coordinate.pathKey
            let parts = pk.split(separator: ".", omittingEmptySubsequences: false)

            if parts.count <= 1 {
                parentByNode[node.id] = nil
            } else {
                let parentPathKey = parts.dropLast().joined(separator: ".")
                // Find the node ID(s) at the parent path key
                if let parentIDs = pathKeyToNodeIDs[parentPathKey], let parentID = parentIDs.first {
                    parentByNode[node.id] = parentID
                    childrenByParent[parentID, default: []].append(node.id)
                } else {
                    // Gap: no node at parent path
                    parentByNode[node.id] = nil
                }
            }
        }

        let rootIDs = nodes
            .filter { parentByNode[$0.id] == nil }
            .map { $0.id }

        let maxDepth = nodeIDToDepth.values.max() ?? 0

        var deepestFirst: [String] = []
        for depth in (0...maxDepth).reversed() {
            if let ids = nodesByDepth[depth] {
                deepestFirst.append(contentsOf: ids)
            }
        }

        // Derive rootPathKeys
        var rootPathKeys: [String] = []
        for pathKey in allPathKeys {
            guard let ids = pathKeyToNodeIDs[pathKey], !ids.isEmpty else { continue }
            guard let depth = nodeIDToDepth[ids.first!] else { continue }
            if depth == 0 {
                rootPathKeys.append(pathKey)
            } else {
                let parentPath = pathKey.split(separator: ".").dropLast().joined(separator: ".")
                if !pathKeyToNodeIDs.keys.contains(parentPath) {
                    rootPathKeys.append(pathKey)
                }
            }
        }

        return TreeIndex(
            childrenByParent: childrenByParent,
            nodesByDepth: nodesByDepth,
            parentByNode: parentByNode,
            rootIDs: rootIDs,
            deepestFirst: deepestFirst,
            pathKeyToNodeIDs: pathKeyToNodeIDs,
            parentToChildren: parentToChildren,
            nodeIDToPathKey: nodeIDToPathKey,
            nodeIDToDepth: nodeIDToDepth,
            rootPathKeys: rootPathKeys.sorted(),
            maxDepth: maxDepth,
            count: nodes.count
        )
    }

    // MARK: - Path-key queries

    /// Node IDs located at the given structural pathKey.
    public func nodeIDs(for pathKey: String) -> [String] {
        pathKeyToNodeIDs[pathKey] ?? []
    }

    /// Node IDs at a specific nesting depth.
    public func nodeIDs(at depth: Int) -> [String] {
        nodesByDepth[depth] ?? []
    }

    /// Child pathKeys of the given pathKey (immediate children only).
    public func children(pathKey: String) -> [String] {
        parentToChildren[pathKey] ?? []
    }

    /// Child node IDs of the node at the given pathKey.
    public func childNodeIDs(pathKey: String) -> [String] {
        children(pathKey: pathKey).flatMap { nodeIDs(for: $0) }
    }

    /// The pathKey of the parent of `pathKey`, if any.
    public func parentPathKey(of pathKey: String) -> String? {
        let parts = pathKey.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count > 1 else { return nil }
        return parts.dropLast().joined(separator: ".")
    }

    /// The pathKey of the parent of `nodeID`, if any.
    public func parentPathKey(ofNodeID nodeID: String) -> String? {
        guard let pathKey = nodeIDToPathKey[nodeID] else { return nil }
        return parentPathKey(of: pathKey)
    }

    /// All descendant pathKeys (recursive) of the given pathKey, in
    /// breadth-first order.
    public func descendantPathKeys(of pathKey: String) -> [String] {
        var result: [String] = []
        var queue = children(pathKey: pathKey)

        while !queue.isEmpty {
            let current = queue.removeFirst()
            result.append(current)
            queue.append(contentsOf: children(pathKey: current))
        }

        return result
    }

    /// All descendant node IDs (recursive) of the given pathKey.
    public func descendantNodeIDs(of pathKey: String) -> [String] {
        descendantPathKeys(of: pathKey).flatMap { nodeIDs(for: $0) }
    }

    /// All node IDs under a given root pathKey, including those at the root
    /// pathKey itself.
    public func subtreeNodeIDs(rootedAt pathKey: String) -> [String] {
        nodeIDs(for: pathKey) + descendantNodeIDs(of: pathKey)
    }

    /// Whether the index contains any nodes at `pathKey`.
    public func contains(pathKey: String) -> Bool {
        pathKeyToNodeIDs[pathKey] != nil
    }

    /// Whether the index contains the given node ID.
    public func contains(nodeID: String) -> Bool {
        nodeIDToPathKey[nodeID] != nil
    }
}
