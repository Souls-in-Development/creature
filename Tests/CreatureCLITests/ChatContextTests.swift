import Testing
import Foundation
@testable import CreatureCLI
import CreatureChat
import CreatureWorkspace
import CreatureTrunk

/// Deterministic (no-model) proof that the pieces `chat --context` wires
/// together — argument parsing, workspace indexing, retrieval, and the
/// shared "Relevant code context:" block builder — actually connect end to
/// end, and that plain `chat` (no `--context`) is untouched. These exercise
/// the exact same `buildContextBlock`/`parseContextArgument` functions
/// `cmdAsk` and `cmdChat` call, not a re-implementation of them.
@Suite struct ChatContextTests {

    private func makeTempWorkspace() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("creature-chat-context-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let source = """
        func calculateTotal(items: [Int]) -> Int {
            items.reduce(0, +)
        }

        func renderBanner() -> String {
            "hello"
        }
        """
        try source.write(to: root.appendingPathComponent("Checkout.swift"), atomically: true, encoding: .utf8)
        return root
    }

    // MARK: - parseContextArgument, chat-shaped usage (no prompt words)

    @Test func parsesChatStyleContextFlagWithNoPromptWords() {
        let (prompt, directory) = parseContextArgument(["--context", "."])
        #expect(prompt.isEmpty)
        #expect(directory == ".")
    }

    @Test func plainChatWithNoContextFlagReturnsNilDirectory() {
        let (prompt, directory) = parseContextArgument([])
        #expect(prompt.isEmpty)
        #expect(directory == nil)
    }

    // MARK: - End-to-end: index -> retrieve -> build block, for a chat turn

    @Test func contextBlockForUserMessageContainsTheRightNode() throws {
        let root = try makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let workspace = WorkspaceIndexer.index(directory: root.path)
        #expect(workspace.fileCount == 1)

        // A chat turn asking about `calculateTotal` by name should retrieve
        // it and NOT pull in the unrelated `renderBanner`. Uses the function
        // name verbatim rather than a paraphrase — ContextRetriever's v0
        // scoring is documented keyword overlap on non-alphanumeric-split
        // tokens, so camelCase names don't decompose into their constituent
        // words (see ContextRetriever.tokenize's doc comment); asking "how
        // do I calculate the total" would not match `calculateTotal` under
        // that honest scope, and this test exercises the real behavior, not
        // a wished-for semantic one.
        let results = ContextRetriever.retrieve(
            query: "calculateTotal",
            trunk: workspace.trunk,
            bridge: workspace.bridge,
            limit: ContextDefaults.contextLimit
        )

        let (block, paths) = buildContextBlock(results: results)
        #expect(!block.isEmpty)
        #expect(paths.contains { $0.contains("calculateTotal") })
        #expect(!paths.contains { $0.contains("renderBanner") })
        #expect(block.contains("calculateTotal"))
    }

    @Test func noMatchingTermsProducesEmptyBlock() throws {
        let root = try makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let workspace = WorkspaceIndexer.index(directory: root.path)

        let results = ContextRetriever.retrieve(
            query: "zzz nonexistent qqq",
            trunk: workspace.trunk,
            bridge: workspace.bridge,
            limit: ContextDefaults.contextLimit
        )

        let (block, paths) = buildContextBlock(results: results)
        #expect(block.isEmpty)
        #expect(paths.isEmpty)
    }
}
