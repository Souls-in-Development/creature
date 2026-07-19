import Testing
import Foundation
@testable import CreatureTrunk

@Suite struct TreeIndexPathKeyTests {

    // MARK: - Helpers

    private func makeNode(id: String, path: [String], kind: String = "func", truthKey: String = "k") -> TrunkNode {
        TrunkNode(
            id: id,
            coordinate: TrunkCoordinate(path: path, kind: kind, truthKey: truthKey),
            channels: []
        )
    }

    /// A small three-level tree: Demo → Greeter → hello
    private func makeDemoTree() -> [TrunkNode] {
        [
            makeNode(id: "module-1", path: ["Demo"], kind: "module", truthKey: "mod"),
            makeNode(id: "type-1",   path: ["Demo", "Greeter"], kind: "struct", truthKey: "type"),
            makeNode(id: "func-1",   path: ["Demo", "Greeter", "hello"], kind: "func", truthKey: "func")
        ]
    }

    // MARK: - Build correctness

    @Test func buildsFromEmptyNodes() {
        let index = TreeIndex.from(nodes: [])
        #expect(index.count == 0)
        #expect(index.maxDepth == 0)
        #expect(index.rootPathKeys.isEmpty)
        #expect(index.pathKeyToNodeIDs.isEmpty)
    }

    @Test func mapsPathKeysToNodeIDs() {
        let index = TreeIndex.from(nodes: makeDemoTree())
        #expect(index.nodeIDs(for: "Demo").sorted() == ["module-1"])
        #expect(index.nodeIDs(for: "Demo.Greeter").sorted() == ["type-1"])
        #expect(index.nodeIDs(for: "Demo.Greeter.hello").sorted() == ["func-1"])
    }

    @Test func computesMaxDepth() {
        let index = TreeIndex.from(nodes: makeDemoTree())
        #expect(index.maxDepth == 3)
    }

    @Test func identifiesRoots() {
        let index = TreeIndex.from(nodes: makeDemoTree())
        #expect(index.rootPathKeys == ["Demo"])
    }

    @Test func multipleRootsWhenNoSharedPrefix() {
        let nodes = [
            makeNode(id: "a", path: ["A"]),
            makeNode(id: "b", path: ["B"])
        ]
        let index = TreeIndex.from(nodes: nodes)
        #expect(index.rootPathKeys.sorted() == ["A", "B"])
    }

    // MARK: - Parent / child queries

    @Test func childrenReturnsImmediateChildrenOnly() {
        let index = TreeIndex.from(nodes: makeDemoTree())
        #expect(index.children(pathKey: "Demo").sorted() == ["Demo.Greeter"])
        #expect(index.children(pathKey: "Demo.Greeter").sorted() == ["Demo.Greeter.hello"])
        #expect(index.children(pathKey: "Demo.Greeter.hello").isEmpty)
    }

    @Test func parentPathKeyOfRootIsNil() {
        let index = TreeIndex.from(nodes: makeDemoTree())
        #expect(index.parentPathKey(of: "Demo") == nil)
    }

    @Test func parentPathKeyForNestedNode() {
        let index = TreeIndex.from(nodes: makeDemoTree())
        #expect(index.parentPathKey(of: "Demo.Greeter") == "Demo")
        #expect(index.parentPathKey(of: "Demo.Greeter.hello") == "Demo.Greeter")
    }

    @Test func parentPathKeyByNodeID() {
        let index = TreeIndex.from(nodes: makeDemoTree())
        #expect(index.parentPathKey(ofNodeID: "module-1") == nil)
        #expect(index.parentPathKey(ofNodeID: "type-1") == "Demo")
        #expect(index.parentPathKey(ofNodeID: "func-1") == "Demo.Greeter")
    }

    // MARK: - Descendants

    @Test func descendantPathKeysAreBreadthFirst() {
        let nodes = [
            makeNode(id: "m", path: ["M"]),
            makeNode(id: "t1", path: ["M", "T1"]),
            makeNode(id: "t2", path: ["M", "T2"]),
            makeNode(id: "f1", path: ["M", "T1", "F1"]),
            makeNode(id: "f2", path: ["M", "T2", "F2"])
        ]
        let index = TreeIndex.from(nodes: nodes)
        let desc = index.descendantPathKeys(of: "M")
        #expect(desc == ["M.T1", "M.T2", "M.T1.F1", "M.T2.F2"])
    }

    @Test func deepestFirstContainsAllNodesInDescendingDepthOrder() {
        let nodes = [
            makeNode(id: "m", path: ["M"]),
            makeNode(id: "t1", path: ["M", "T1"]),
            makeNode(id: "t2", path: ["M", "T2"]),
            makeNode(id: "f1", path: ["M", "T1", "F1"]),
            makeNode(id: "f2", path: ["M", "T2", "F2"])
        ]
        let index = TreeIndex.from(nodes: nodes)
        #expect(index.deepestFirst.prefix(2).sorted() == ["f1", "f2"]) // depth 3
        #expect(index.deepestFirst.dropFirst(2).prefix(2).sorted() == ["t1", "t2"]) // depth 2
        #expect(index.deepestFirst.last == "m") // depth 1
    }

    @Test func subtreeIncludesRootAndDescendants() {
        let index = TreeIndex.from(nodes: makeDemoTree())
        let subtree = index.subtreeNodeIDs(rootedAt: "Demo")
        #expect(Set(subtree) == Set(["module-1", "type-1", "func-1"]))
    }

    // MARK: - Sparse tree

    @Test func sparseTreeStillIndexesCorrectly() {
        let nodes = [
            makeNode(id: "type-1", path: ["Demo", "Greeter"], kind: "struct"),
            makeNode(id: "func-1", path: ["Demo", "Greeter", "hello"], kind: "func")
        ]
        let index = TreeIndex.from(nodes: nodes)
        #expect(index.rootPathKeys == ["Demo.Greeter"])
        #expect(index.children(pathKey: "Demo.Greeter") == ["Demo.Greeter.hello"])
        #expect(index.children(pathKey: "Demo") == ["Demo.Greeter"])
    }

    // MARK: - Multiple nodes at same path

    @Test func multipleNodesAtSamePathKeyAreGrouped() {
        let coord = TrunkCoordinate(path: ["X"], kind: "func", truthKey: "k")
        let nodes = [
            TrunkNode(id: "n1", coordinate: coord, channels: []),
            TrunkNode(id: "n2", coordinate: coord, channels: [])
        ]
        let index = TreeIndex.from(nodes: nodes)
        #expect(index.nodeIDs(for: "X").sorted() == ["n1", "n2"])
        #expect(index.count == 2)
    }

    // MARK: - Contains

    @Test func containsPathKeyAndNodeID() {
        let index = TreeIndex.from(nodes: makeDemoTree())
        #expect(index.contains(pathKey: "Demo"))
        #expect(index.contains(pathKey: "Demo.Greeter"))
        #expect(!index.contains(pathKey: "No.Such.Path"))
        #expect(index.contains(nodeID: "func-1"))
        #expect(!index.contains(nodeID: "ghost"))
    }

    // MARK: - Codable round trip

    @Test func codableRoundTrip() throws {
        let original = TreeIndex.from(nodes: makeDemoTree())
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TreeIndex.self, from: data)

        #expect(decoded.count == original.count)
        #expect(decoded.maxDepth == original.maxDepth)
        #expect(decoded.rootPathKeys == original.rootPathKeys)
        #expect(decoded.pathKeyToNodeIDs == original.pathKeyToNodeIDs)
        #expect(decoded.parentToChildren == original.parentToChildren)
        #expect(decoded.childrenByParent == original.childrenByParent)
        #expect(decoded.parentByNode == original.parentByNode)
        #expect(decoded.nodesByDepth == original.nodesByDepth)
        #expect(decoded.rootIDs == original.rootIDs)
        #expect(decoded.deepestFirst == original.deepestFirst)
    }

    // MARK: - CodeTrunk integration

    @Test func codeTrunkBuildsTreeIndex() {
        var trunk = CodeTrunk()
        for node in makeDemoTree() {
            trunk.add(node)
        }
        let index = trunk.buildTreeIndex()
        #expect(index.count == 3)
        #expect(index.nodeIDs(for: "Demo") == ["module-1"])
    }

    @Test func codeTrunkTreeIndexOnEmptyTrunk() {
        let trunk = CodeTrunk()
        let index = trunk.buildTreeIndex()
        #expect(index.count == 0)
    }
}
