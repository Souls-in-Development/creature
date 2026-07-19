import Testing
import Foundation
@testable import CreatureTrunk

@Suite struct CodeIngesterTests {

    @Test func ingestBuildsChannelsAndCoordinate() {
        let source = "func add(a: Int, b: Int) -> Int { a + b }"
        let node = CodeIngester.ingest(source: source, language: "swift", path: ["Math", "add"])

        #expect(node.coordinate.path == ["Math", "add"])
        #expect(node.coordinate.depth == 2)
        #expect(node.channel(at: 1)?.content == source)
        #expect(node.channel(at: 1)?.language == "swift")
        #expect(node.channel(at: 0)?.language == "rosetta")
        #expect(node.coordinate.truthKey == CodeIngester.truthHash(of: node.channel(at: 0)!.content))
    }

    @Test func swiftSkeletonExtractsFuncNameAndArity() {
        let source = "func add(a: Int, b: Int) -> Int { a + b }"
        let skeleton = CodeIngester.normalize(source: source, language: "swift")
        #expect(skeleton == "func add/2")
    }

    @Test func pythonSkeletonExtractsDefNameAndArity() {
        let source = "def add(a, b):\n    return a + b"
        let skeleton = CodeIngester.normalize(source: source, language: "python")
        #expect(skeleton == "func add/2")
    }

    @Test func swiftAndPythonSameShapeProduceSameSkeleton() {
        let swiftSource = "func add(a: Int, b: Int) -> Int { return a + b }"
        let pythonSource = "def add(a, b):\n    return a + b"

        let swiftSkeleton = CodeIngester.normalize(source: swiftSource, language: "swift")
        let pythonSkeleton = CodeIngester.normalize(source: pythonSource, language: "python")

        #expect(swiftSkeleton == pythonSkeleton)
    }

    @Test func unknownLanguageProducesEmptySkeleton() {
        let skeleton = CodeIngester.normalize(source: "whatever(1,2,3)", language: "cobol")
        #expect(skeleton.isEmpty)
    }

    @Test func multipleDeclarationsAreSortedInSkeleton() {
        let source = """
        struct Point {}
        func add(a: Int, b: Int) -> Int { a + b }
        class Renderer {}
        """
        let skeleton = CodeIngester.normalize(source: source, language: "swift")
        #expect(skeleton == "class Renderer/0\nfunc add/2\nstruct Point/0")
    }

    /// The cross-language demo required by the trunk v0 spec: ingest a small
    /// Swift snippet and a Python snippet that declare the same-shaped
    /// function, then check whether `CodeTrunk.nodesSharing(truthKey:)`
    /// links them. Reported honestly either way — v0's simple normalizer is
    /// declaration-shape matching, not full semantic equivalence.
    @Test func crossLanguageDemoLinksSameShapedFunctions() {
        var trunk = CodeTrunk()

        let swiftNode = CodeIngester.ingest(
            source: "func add(a: Int, b: Int) -> Int { return a + b }",
            language: "swift",
            path: ["Math", "add.swift"]
        )
        let pythonNode = CodeIngester.ingest(
            source: "def add(a, b):\n    return a + b",
            language: "python",
            path: ["math", "add.py"]
        )

        trunk.add(swiftNode)
        trunk.add(pythonNode)

        let linked = trunk.nodesSharing(truthKey: swiftNode.coordinate.truthKey)

        // v0 result, stated plainly: same-shaped func/2 declarations in
        // Swift and Python normalize to the identical skeleton
        // ("func add/2"), so they DO share a truthKey and DO link here.
        #expect(linked.count == 2)
        #expect(Set(linked.map(\.id)) == Set([swiftNode.id, pythonNode.id]))
    }

    /// A shape mismatch (different arity) must NOT be linked — the mechanism
    /// distinguishes, it doesn't just always match.
    @Test func crossLanguageDemoDoesNotLinkDifferentShapes() {
        var trunk = CodeTrunk()

        let swiftNode = CodeIngester.ingest(
            source: "func add(a: Int, b: Int) -> Int { return a + b }",
            language: "swift",
            path: ["Math", "add.swift"]
        )
        let pythonNode = CodeIngester.ingest(
            source: "def add(a, b, c):\n    return a + b + c",
            language: "python",
            path: ["math", "add3.py"]
        )

        trunk.add(swiftNode)
        trunk.add(pythonNode)

        let linked = trunk.nodesSharing(truthKey: swiftNode.coordinate.truthKey)
        #expect(linked.count == 1)
        #expect(linked.first?.id == swiftNode.id)
    }
}
