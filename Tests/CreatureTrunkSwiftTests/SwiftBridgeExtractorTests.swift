import Testing
import Foundation
@testable import CreatureTrunkSwift
import CreatureTrunk

@Suite struct SwiftBridgeExtractorTests {

    // MARK: - Basic edge extraction

    @Test func twoFunctionsWhereOneCallsTheOtherProducesOneEdge() {
        let source = """
        func greet() { hello() }
        func hello() {}
        """
        let (nodes, _, edges) = SwiftIndexer.indexWithBridge(source: source, module: "Demo")

        #expect(nodes.count == 2)
        #expect(edges.count == 1)

        let greetNode = nodes.first { $0.coordinate.path == ["Demo", "greet"] }!
        let helloNode = nodes.first { $0.coordinate.path == ["Demo", "hello"] }!

        #expect(edges[0].source == greetNode.id)
        #expect(edges[0].targetTruthKey == helloNode.coordinate.truthKey)
        #expect(edges[0].kind == .call)
    }

    @Test func memberCallExtractsEdge() {
        let source = """
        struct Calculator {
            func add(a: Int, b: Int) -> Int { a + b }
            func compute() -> Int { self.add(a: 1, b: 2) }
        }
        """
        let (nodes, _, edges) = SwiftIndexer.indexWithBridge(source: source, module: "Demo")

        let computeNode = nodes.first { $0.coordinate.path == ["Demo", "Calculator", "compute"] }!
        let addNode = nodes.first { $0.coordinate.path == ["Demo", "Calculator", "add"] }!

        let computeEdges = edges.filter { $0.source == computeNode.id }
        #expect(computeEdges.count == 1)
        #expect(computeEdges[0].targetTruthKey == addNode.coordinate.truthKey)
    }

    @Test func functionWithNoCallsProducesNoEdges() {
        let source = """
        func isolated() { }
        """
        let (_, _, edges) = SwiftIndexer.indexWithBridge(source: source, module: "Demo")
        #expect(edges.isEmpty)
    }

    @Test func nestedCallInsideStructProducesStructuralNodesAndEdge() {
        let source = """
        struct Box {
            func wrap() -> String { "box" }
            func open() -> String { wrap() }
        }
        """
        let (nodes, _, edges) = SwiftIndexer.indexWithBridge(source: source, module: "Demo")

        let boxNode = nodes.first { $0.coordinate.path == ["Demo", "Box"] }
        #expect(boxNode != nil)

        let wrapNode = nodes.first { $0.coordinate.path == ["Demo", "Box", "wrap"] }!
        let openNode = nodes.first { $0.coordinate.path == ["Demo", "Box", "open"] }!

        #expect(edges.count == 1)
        #expect(edges[0].source == openNode.id)
        #expect(edges[0].targetTruthKey == wrapNode.coordinate.truthKey)
    }

    // MARK: - Cross-language implication

    @Test func twoCallsWithSameArityProduceSameTruthKey() {
        let source = """
        func add(a: Int, b: Int) -> Int { a + b }
        func caller1() { add(a: 1, b: 2) }
        func caller2() { add(a: 3, b: 4) }
        """
        let (nodes, _, edges) = SwiftIndexer.indexWithBridge(source: source, module: "Demo")

        let addNode = nodes.first { $0.coordinate.path == ["Demo", "add"] }!
        let caller1Node = nodes.first { $0.coordinate.path == ["Demo", "caller1"] }!
        let caller2Node = nodes.first { $0.coordinate.path == ["Demo", "caller2"] }!

        let caller1Edges = edges.filter { $0.source == caller1Node.id }
        let caller2Edges = edges.filter { $0.source == caller2Node.id }

        #expect(caller1Edges.count == 1)
        #expect(caller2Edges.count == 1)
        #expect(caller1Edges[0].targetTruthKey == caller2Edges[0].targetTruthKey)
        #expect(caller1Edges[0].targetTruthKey == addNode.coordinate.truthKey)
    }

    @Test func unresolvedEdgesResolveToSameTarget() {
        let source = """
        func add(a: Int, b: Int) -> Int { a + b }
        func caller1() { add(a: 1, b: 2) }
        func caller2() { add(a: 3, b: 4) }
        """
        let (nodes, _, edges) = SwiftIndexer.indexWithBridge(source: source, module: "Demo")

        let trunk = CodeTrunk(nodes: nodes)
        let bridge = TrunkBridge.resolve(unresolved: edges, against: trunk)

        let addNode = nodes.first { $0.coordinate.path == ["Demo", "add"] }!
        let caller1Node = nodes.first { $0.coordinate.path == ["Demo", "caller1"] }!
        let caller2Node = nodes.first { $0.coordinate.path == ["Demo", "caller2"] }!

        let caller1Targets = bridge.targets(of: caller1Node.id)
        let caller2Targets = bridge.targets(of: caller2Node.id)

        #expect(caller1Targets == [addNode.id])
        #expect(caller2Targets == [addNode.id])
    }
}
