import Testing
import Foundation
@testable import CreatureTrunkSwift
import CreatureTrunk

@Suite struct SwiftIndexerTests {

    /// The spec's worked example: a struct with two methods, plus a
    /// top-level func. Verifies the real nested tree — the struct's methods
    /// land at path length 3 / depth 2, not flattened alongside the struct.
    static let sample = """
    struct Greeter {
        func hello() -> String { "hi" }
        func bye(name: String) -> String { "bye \\(name)" }
    }

    func topLevel(x: Int, y: Int) -> Int { x + y }
    """

    @Test func indexesStructAndItsMethodsAtCorrectDepth() {
        let nodes = SwiftIndexer.index(source: Self.sample, module: "Demo")

        let structNode = nodes.first { $0.coordinate.path == ["Demo", "Greeter"] }
        #expect(structNode != nil)
        #expect(structNode?.coordinate.kind == "struct")
        #expect(structNode?.coordinate.depth == 2)

        let helloNode = nodes.first { $0.coordinate.path == ["Demo", "Greeter", "hello"] }
        #expect(helloNode != nil)
        #expect(helloNode?.coordinate.kind == "func")
        #expect(helloNode?.coordinate.depth == 3)

        let byeNode = nodes.first { $0.coordinate.path == ["Demo", "Greeter", "bye"] }
        #expect(byeNode != nil)
        #expect(byeNode?.coordinate.depth == 3)
    }

    @Test func indexesTopLevelFuncAtModuleDepth() {
        let nodes = SwiftIndexer.index(source: Self.sample, module: "Demo")

        let topLevelNode = nodes.first { $0.coordinate.path == ["Demo", "topLevel"] }
        #expect(topLevelNode != nil)
        #expect(topLevelNode?.coordinate.kind == "func")
        #expect(topLevelNode?.coordinate.depth == 2)
    }

    @Test func channelZeroSkeletonsReflectRealArity() {
        let nodes = SwiftIndexer.index(source: Self.sample, module: "Demo")

        let helloNode = nodes.first { $0.coordinate.path == ["Demo", "Greeter", "hello"] }
        #expect(helloNode?.channel(at: 0)?.content == "func hello/0")

        let byeNode = nodes.first { $0.coordinate.path == ["Demo", "Greeter", "bye"] }
        #expect(byeNode?.channel(at: 0)?.content == "func bye/1")

        let topLevelNode = nodes.first { $0.coordinate.path == ["Demo", "topLevel"] }
        #expect(topLevelNode?.channel(at: 0)?.content == "func topLevel/2")

        let structNode = nodes.first { $0.coordinate.path == ["Demo", "Greeter"] }
        #expect(structNode?.channel(at: 0)?.content == "struct Greeter")
    }

    @Test func channelOneCarriesTheDeclarationsOwnSourceText() {
        let nodes = SwiftIndexer.index(source: Self.sample, module: "Demo")

        let helloNode = nodes.first { $0.coordinate.path == ["Demo", "Greeter", "hello"] }
        #expect(helloNode?.channel(at: 1)?.language == "swift")
        #expect(helloNode?.channel(at: 1)?.content.contains("func hello() -> String") == true)
        // Channel 1 is scoped to this declaration only, not the whole file.
        #expect(helloNode?.channel(at: 1)?.content.contains("topLevel") == false)
    }

    @Test func truthKeyMatchesHashOfChannelZero() {
        let nodes = SwiftIndexer.index(source: Self.sample, module: "Demo")
        for node in nodes {
            guard let skeleton = node.channel(at: 0)?.content else {
                Issue.record("missing channel 0 for \(node.id)")
                continue
            }
            #expect(node.coordinate.truthKey == CodeIngester.truthHash(of: skeleton))
        }
    }

    @Test func nestedTypeInsideTypeReachesDepthThree() {
        let source = """
        struct Outer {
            struct Inner {
                func deepFunc() {}
            }
        }
        """
        let nodes = SwiftIndexer.index(source: source, module: "Demo")

        let inner = nodes.first { $0.coordinate.path == ["Demo", "Outer", "Inner"] }
        #expect(inner?.coordinate.depth == 3)
        #expect(inner?.coordinate.kind == "struct")

        let deepFunc = nodes.first { $0.coordinate.path == ["Demo", "Outer", "Inner", "deepFunc"] }
        #expect(deepFunc?.coordinate.depth == 4)
        #expect(deepFunc?.coordinate.kind == "func")
    }

    @Test func classActorProtocolExtensionAreRecognized() {
        let source = """
        class MyClass {}
        actor MyActor {}
        protocol MyProtocol {}
        extension MyClass {
            func extraMethod() {}
        }
        """
        let nodes = SwiftIndexer.index(source: source, module: "Demo")

        #expect(nodes.contains { $0.coordinate.path == ["Demo", "MyClass"] && $0.coordinate.kind == "class" })
        #expect(nodes.contains { $0.coordinate.path == ["Demo", "MyActor"] && $0.coordinate.kind == "actor" })
        #expect(nodes.contains { $0.coordinate.path == ["Demo", "MyProtocol"] && $0.coordinate.kind == "protocol" })
        #expect(nodes.contains { $0.coordinate.path == ["Demo", "MyClass"] && $0.coordinate.kind == "extension" })

        let extraMethod = nodes.first { $0.coordinate.path == ["Demo", "MyClass", "extraMethod"] }
        #expect(extraMethod != nil)
        #expect(extraMethod?.coordinate.depth == 3)
    }

    @Test func initializerIsIndexedWithArity() {
        let source = """
        struct Point {
            init(x: Int, y: Int) {}
        }
        """
        let nodes = SwiftIndexer.index(source: source, module: "Demo")

        let initNode = nodes.first { $0.coordinate.path == ["Demo", "Point", "init"] }
        #expect(initNode != nil)
        #expect(initNode?.coordinate.kind == "init")
        #expect(initNode?.channel(at: 0)?.content == "init/2")
    }

    @Test func varAndLetAreIndexedTopLevelAndNested() {
        let source = """
        let topLevelConstant = 42

        struct Config {
            var name: String = "x"
            let version: Int = 1
        }
        """
        let nodes = SwiftIndexer.index(source: source, module: "Demo")

        let topConst = nodes.first { $0.coordinate.path == ["Demo", "topLevelConstant"] }
        #expect(topConst?.coordinate.kind == "let")

        let name = nodes.first { $0.coordinate.path == ["Demo", "Config", "name"] }
        #expect(name?.coordinate.kind == "var")
        #expect(name?.coordinate.depth == 3)

        let version = nodes.first { $0.coordinate.path == ["Demo", "Config", "version"] }
        #expect(version?.coordinate.kind == "let")
    }

    @Test func enumCasesAreCountedInSkeleton() {
        let source = """
        enum Direction {
            case north
            case south, east, west
        }
        """
        let nodes = SwiftIndexer.index(source: source, module: "Demo")

        let enumNode = nodes.first { $0.coordinate.path == ["Demo", "Direction"] }
        #expect(enumNode?.coordinate.kind == "enum")
        #expect(enumNode?.channel(at: 0)?.content == "enum Direction/4")
    }

    @Test func multipleBindingsInOneVarDeclProduceSeparateNodes() {
        let source = "var a, b: Int"
        let nodes = SwiftIndexer.index(source: source, module: "Demo")

        #expect(nodes.contains { $0.coordinate.path == ["Demo", "a"] })
        #expect(nodes.contains { $0.coordinate.path == ["Demo", "b"] })
    }

    /// The trunk demo: indexing a real file from this very package should
    /// produce a sensible, non-empty structural tree (not asserting exact
    /// shape here — see the CLI/demo output for the human-readable tree).
    @Test func indexingARealTrunkFileProducesNonEmptyTree() throws {
        let path = "Sources/CreatureTrunk/TrunkNode.swift"
        let source = try String(contentsOfFile: path, encoding: .utf8)
        let nodes = SwiftIndexer.index(source: source, module: "CreatureTrunk")

        #expect(!nodes.isEmpty)
        #expect(nodes.contains { $0.coordinate.path == ["CreatureTrunk", "TrunkNode"] && $0.coordinate.kind == "struct" })
    }
}

@Suite struct SwiftIndexerStatusTests {

    @Test func cleanSourceProducesAllGreenStatus() {
        let (nodes, status) = SwiftIndexer.indexWithStatus(source: SwiftIndexerTests.sample, module: "Demo")

        #expect(!nodes.isEmpty)
        #expect(status.count == nodes.count)
        for node in nodes {
            #expect(status[node.id] == .green)
        }
    }

    @Test func statusMapCoversSameNodesAsPlainIndex() {
        let plainNodes = SwiftIndexer.index(source: SwiftIndexerTests.sample, module: "Demo")
        let (statusNodes, status) = SwiftIndexer.indexWithStatus(source: SwiftIndexerTests.sample, module: "Demo")

        #expect(Set(plainNodes.map(\.id)) == Set(statusNodes.map(\.id)))
        #expect(Set(status.keys) == Set(statusNodes.map(\.id)))
    }

    /// A deliberate syntax error: an unterminated function body (missing
    /// closing brace). SwiftSyntax still produces a tree — SwiftParser is
    /// error-recovering — but the offending declaration's subtree carries
    /// `hasError == true`, which `indexWithStatus` must surface as `.red`.
    @Test func declarationWithSyntaxErrorIsRed() {
        let source = """
        struct Broken {
            func bad( -> Int {
                return 1
            }
        }
        """
        let (nodes, status) = SwiftIndexer.indexWithStatus(source: source, module: "Demo")

        let badFunc = nodes.first { $0.coordinate.path == ["Demo", "Broken", "bad"] }
        #expect(badFunc != nil)
        #expect(status[badFunc!.id] == .red)
    }

    @Test func unrelatedDeclarationsStayGreenWhenAnotherIsBroken() {
        let source = """
        struct Broken {
            func bad( -> Int {
                return 1
            }
        }

        func healthy(x: Int) -> Int { x + 1 }
        """
        let (nodes, status) = SwiftIndexer.indexWithStatus(source: source, module: "Demo")

        let healthyFunc = nodes.first { $0.coordinate.path == ["Demo", "healthy"] }
        #expect(healthyFunc != nil)
        #expect(status[healthyFunc!.id] == .green)
    }
}
