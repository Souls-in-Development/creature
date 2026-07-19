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
struct PythonIndexerTests {

    /// The spec's worked example: a class with two methods, plus a top-level
    /// def. Verifies the real nested tree — the class's methods land at
    /// path length 3 / depth 3, not flattened alongside the class, and
    /// self/cls is dropped from method arity.
    static let sample = """
    class Greeter:
        def hello(self):
            return "hi"

        def bye(self, name):
            return "bye " + name

    def top_level(x, y):
        return x + y
    """

    @Test func indexesClassAndItsMethodsAtCorrectDepth() {
        let nodes = PythonIndexer.index(source: Self.sample, module: "Demo")

        let classNode = nodes.first { $0.coordinate.path == ["Demo", "Greeter"] }
        #expect(classNode != nil)
        #expect(classNode?.coordinate.kind == "class")
        #expect(classNode?.coordinate.depth == 2)

        let helloNode = nodes.first { $0.coordinate.path == ["Demo", "Greeter", "hello"] }
        #expect(helloNode != nil)
        #expect(helloNode?.coordinate.kind == "func")
        #expect(helloNode?.coordinate.depth == 3)

        let byeNode = nodes.first { $0.coordinate.path == ["Demo", "Greeter", "bye"] }
        #expect(byeNode != nil)
        #expect(byeNode?.coordinate.depth == 3)
    }

    @Test func indexesTopLevelDefAtModuleDepth() {
        let nodes = PythonIndexer.index(source: Self.sample, module: "Demo")

        let topLevelNode = nodes.first { $0.coordinate.path == ["Demo", "top_level"] }
        #expect(topLevelNode != nil)
        #expect(topLevelNode?.coordinate.kind == "func")
        #expect(topLevelNode?.coordinate.depth == 2)
    }

    @Test func selfIsDroppedFromMethodArity() {
        let nodes = PythonIndexer.index(source: Self.sample, module: "Demo")

        let helloNode = nodes.first { $0.coordinate.path == ["Demo", "Greeter", "hello"] }
        #expect(helloNode?.channel(at: 0)?.content == "func hello/0")

        let byeNode = nodes.first { $0.coordinate.path == ["Demo", "Greeter", "bye"] }
        #expect(byeNode?.channel(at: 0)?.content == "func bye/1")

        let topLevelNode = nodes.first { $0.coordinate.path == ["Demo", "top_level"] }
        #expect(topLevelNode?.channel(at: 0)?.content == "func top_level/2")

        let classNode = nodes.first { $0.coordinate.path == ["Demo", "Greeter"] }
        #expect(classNode?.channel(at: 0)?.content == "class Greeter")
    }

    @Test func channelOneIsLabelledPython() {
        let nodes = PythonIndexer.index(source: Self.sample, module: "Demo")

        let helloNode = nodes.first { $0.coordinate.path == ["Demo", "Greeter", "hello"] }
        #expect(helloNode?.channel(at: 1)?.language == "python")
    }

    @Test func truthKeyMatchesHashOfChannelZero() {
        let nodes = PythonIndexer.index(source: Self.sample, module: "Demo")
        for node in nodes {
            guard let skeleton = node.channel(at: 0)?.content else {
                Issue.record("missing channel 0 for \(node.id)")
                continue
            }
            #expect(node.coordinate.truthKey == CodeIngester.truthHash(of: skeleton))
        }
    }

    @Test func topLevelAssignmentIsIndexedAsVar() {
        let source = """
        CONSTANT = 42

        class Config:
            name = "x"
        """
        let nodes = PythonIndexer.index(source: source, module: "Demo")

        let constant = nodes.first { $0.coordinate.path == ["Demo", "CONSTANT"] }
        #expect(constant?.coordinate.kind == "var")

        let name = nodes.first { $0.coordinate.path == ["Demo", "Config", "name"] }
        #expect(name?.coordinate.kind == "var")
        #expect(name?.coordinate.depth == 3)
    }

    @Test func nestedClassInsideClassReachesDepthThree() {
        let source = """
        class Outer:
            class Inner:
                def deep_func(self):
                    pass
        """
        let nodes = PythonIndexer.index(source: source, module: "Demo")

        let inner = nodes.first { $0.coordinate.path == ["Demo", "Outer", "Inner"] }
        #expect(inner?.coordinate.depth == 3)
        #expect(inner?.coordinate.kind == "class")

        let deepFunc = nodes.first { $0.coordinate.path == ["Demo", "Outer", "Inner", "deep_func"] }
        #expect(deepFunc?.coordinate.depth == 4)
        #expect(deepFunc?.coordinate.kind == "func")
    }

    @Test func staticFunctionArityCountsAllParameters() {
        // A free function's arity counts every positional/keyword parameter
        // — there is no self/cls to drop outside a class body.
        let source = "def add(a, b):\n    return a + b\n"
        let nodes = PythonIndexer.index(source: source, module: "Demo")

        let add = nodes.first { $0.coordinate.path == ["Demo", "add"] }
        #expect(add?.channel(at: 0)?.content == "func add/2")
    }

    /// The trunk demo: indexing a real, non-trivial snippet should produce a
    /// sensible non-empty structural tree.
    @Test func indexingProducesNonEmptyTree() {
        let nodes = PythonIndexer.index(source: Self.sample, module: "Demo")
        #expect(!nodes.isEmpty)
        #expect(nodes.contains { $0.coordinate.path == ["Demo", "Greeter"] && $0.coordinate.kind == "class" })
    }
}

@Suite struct PythonIndexerStatusTests {

    @Test func cleanSourceProducesAllGreenStatus() {
        let (nodes, status) = PythonIndexer.indexWithStatus(source: PythonIndexerTests.sample, module: "Demo")

        #expect(!nodes.isEmpty)
        #expect(status.count == nodes.count)
        for node in nodes {
            #expect(status[node.id] == .green)
        }
    }

    @Test func statusMapCoversSameNodesAsPlainIndex() {
        let plainNodes = PythonIndexer.index(source: PythonIndexerTests.sample, module: "Demo")
        let (statusNodes, status) = PythonIndexer.indexWithStatus(source: PythonIndexerTests.sample, module: "Demo")

        #expect(Set(plainNodes.map(\.id)) == Set(statusNodes.map(\.id)))
        #expect(Set(status.keys) == Set(statusNodes.map(\.id)))
    }

    /// A deliberate Python syntax error: an unterminated parameter list.
    /// `ast.parse` raises `SyntaxError` — `indexWithStatus` must surface that
    /// as a `.red` node rather than crashing or silently returning nothing.
    @Test func syntaxErrorProducesRedStatus() {
        let source = """
        class Broken:
            def bad(:
                return 1
        """
        let (nodes, status) = PythonIndexer.indexWithStatus(source: source, module: "Demo")

        #expect(!nodes.isEmpty)
        #expect(nodes.allSatisfy { status[$0.id] == .red })
    }
}

/// The cross-language linking proof: a Swift `func add(a: Int, b: Int)` and a
/// Python `def add(a, b)` must land in the SAME `CodeTrunk` sharing a
/// `truthKey`, and `CodeTrunk.nodesSharing(truthKey:)` must return BOTH. This
/// is the whole point of the trunk (see
/// `docs/plans/2026-07-05-creature-cursor-competitor-architecture.md` §3) —
/// a Swift and a Python implementation of the same-shaped function are found
/// to be the same thing at the trunk, with zero language-specific glue in
/// `CodeTrunk` itself.
@Suite struct CrossLanguageLinkingTests {

    @Test func swiftAndPythonAddShareATruthKeyAndAreBothFound() {
        let swiftSource = "func add(a: Int, b: Int) -> Int { a + b }"
        let pythonSource = "def add(a, b):\n    return a + b\n"

        let swiftNodes = SwiftIndexer.index(source: swiftSource, module: "SwiftDemo")
        let pythonNodes = PythonIndexer.index(source: pythonSource, module: "PythonDemo")

        let swiftAdd = swiftNodes.first { $0.coordinate.path == ["SwiftDemo", "add"] }
        let pythonAdd = pythonNodes.first { $0.coordinate.path == ["PythonDemo", "add"] }
        #expect(swiftAdd != nil)
        #expect(pythonAdd != nil)

        // Both normalize to the identical Channel-0 skeleton.
        #expect(swiftAdd?.channel(at: 0)?.content == "func add/2")
        #expect(pythonAdd?.channel(at: 0)?.content == "func add/2")
        #expect(swiftAdd?.coordinate.truthKey == pythonAdd?.coordinate.truthKey)

        var trunk = CodeTrunk()
        for node in swiftNodes { trunk.add(node) }
        for node in pythonNodes { trunk.add(node) }

        let shared = trunk.nodesSharing(truthKey: swiftAdd!.coordinate.truthKey)
        #expect(Set(shared.map(\.id)) == Set([swiftAdd!.id, pythonAdd!.id]))

        // Different languages, distinct chroma on Channel 1.
        #expect(swiftAdd?.channel(at: 1)?.language == "swift")
        #expect(pythonAdd?.channel(at: 1)?.language == "python")
        #expect(swiftAdd?.channel(at: 1)?.colour != pythonAdd?.channel(at: 1)?.colour)
    }
}
