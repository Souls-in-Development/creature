import Testing
import Foundation
@testable import CreatureTrunkPython
import CreatureTrunk
import CreatureTrunkSwift


/// These suites exercise the `python3` + `ast` path specifically. Where python3
/// is absent (a bare Linux container, a stripped CI image), `PythonIndexer`
/// deliberately degrades to its regex fallback, which produces a different node
/// shape — so asserting AST-path results there tests nothing and force-unwraps
/// nil. Skip honestly instead of failing, exactly as the external-validator
/// probe tests do.
@Suite(.enabled(if: PythonIndexer.locatePython3() != nil))
struct PythonBridgeExtractorTests {

    @Test func twoFunctionsOneCallsTheOtherProducesEdge() {
        let source = """
        def add(a, b):
            return a + b

        def calc():
            return add(1, 2)
        """
        let result = PythonIndexer.indexWithBridge(source: source, module: "Demo")

        let calcNode = result.nodes.first { $0.coordinate.path == ["Demo", "calc"] }!

        #expect(result.edges.count == 1)
        let edge = result.edges.first!
        #expect(edge.source == calcNode.id)
        #expect(edge.targetTruthKey == CodeIngester.truthHash(of: "func add/2"))
        #expect(edge.kind == .call)
    }

    @Test func classMethodSelfCallExtractsEdge() {
        let source = """
        class Calculator:
            def add(self, a, b):
                return a + b

            def calc(self):
                return self.add(1, 2)
        """
        let result = PythonIndexer.indexWithBridge(source: source, module: "Demo")

        let calcMethod = result.nodes.first { $0.coordinate.path == ["Demo", "Calculator", "calc"] }!

        #expect(result.edges.count == 1)
        let edge = result.edges.first!
        #expect(edge.source == calcMethod.id)
        #expect(edge.targetTruthKey == CodeIngester.truthHash(of: "func add/2"))
        #expect(edge.kind == .call)
    }

    @Test func functionWithNoCallsProducesNoEdges() {
        let source = """
        def foo():
            return 1
        """
        let result = PythonIndexer.indexWithBridge(source: source, module: "Demo")

        #expect(result.edges.isEmpty)
    }

    @Test func crossLanguageResolvesToEquivalentSwiftFunction() {
        let pythonSource = """
        def add(a, b):
            return a + b

        def caller():
            return add(1, 2)
        """
        let swiftSource = "func add(a: Int, b: Int) -> Int { a + b }"

        let pythonResult = PythonIndexer.indexWithBridge(source: pythonSource, module: "PyDemo")
        let swiftNodes = SwiftIndexer.index(source: swiftSource, module: "SwiftDemo")

        var trunk = CodeTrunk()
        for node in pythonResult.nodes { trunk.add(node) }
        for node in swiftNodes { trunk.add(node) }

        let bridge = TrunkBridge.resolve(unresolved: pythonResult.edges, against: trunk)

        let callerNode = pythonResult.nodes.first { $0.coordinate.path == ["PyDemo", "caller"] }!
        let swiftAdd = swiftNodes.first { $0.coordinate.path == ["SwiftDemo", "add"] }!
        let pythonAdd = pythonResult.nodes.first { $0.coordinate.path == ["PyDemo", "add"] }!

        #expect(bridge.edges.count == 2)
        #expect(bridge.edges.contains { $0.source == callerNode.id && $0.target == swiftAdd.id })
        #expect(bridge.edges.contains { $0.source == callerNode.id && $0.target == pythonAdd.id })
    }

    @Test func indexWithBridgeReturnsSameNodesAsIndexWithStatus() {
        let source = """
        def add(a, b):
            return a + b

        def calc():
            return add(1, 2)
        """
        let (nodes, status) = PythonIndexer.indexWithStatus(source: source, module: "Demo")
        let (bridgeNodes, bridgeStatus, edges) = PythonIndexer.indexWithBridge(source: source, module: "Demo")

        #expect(Set(nodes.map(\.id)) == Set(bridgeNodes.map(\.id)))
        #expect(status == bridgeStatus)
        #expect(!edges.isEmpty)
    }
}
