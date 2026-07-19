import Testing
import Foundation
@testable import CreatureTrunk

@Suite struct ContextRetrieverTests {

    /// Build a small in-memory trunk: `calculateTotal` (a function) and
    /// `formatCurrency` (a function `calculateTotal` calls), plus an unrelated
    /// `parseInput` function — enough to exercise scoring AND bridge
    /// expansion without touching disk or a real tentacle.
    private func makeTrunk() -> (trunk: CodeTrunk, bridge: TrunkBridge) {
        var trunk = CodeTrunk()

        let calcCoord = TrunkCoordinate(path: ["Billing", "calculateTotal"], kind: "func", truthKey: "calc_hash")
        let calcNode = TrunkNode(
            id: "calc",
            coordinate: calcCoord,
            channels: [
                TrunkChannel(index: 0, language: "rosetta", content: "func calculateTotal/2"),
                TrunkChannel(index: 1, language: "swift", content: "func calculateTotal(items: [Item], tax: Double) -> Double { formatCurrency(total) }")
            ]
        )
        trunk.add(calcNode)

        let formatCoord = TrunkCoordinate(path: ["Billing", "formatCurrency"], kind: "func", truthKey: "format_hash")
        let formatNode = TrunkNode(
            id: "format",
            coordinate: formatCoord,
            channels: [
                TrunkChannel(index: 0, language: "rosetta", content: "func formatCurrency/1"),
                TrunkChannel(index: 1, language: "swift", content: "func formatCurrency(amount: Double) -> String { \"$\\(amount)\" }")
            ]
        )
        trunk.add(formatNode)

        let parseCoord = TrunkCoordinate(path: ["Input", "parseInput"], kind: "func", truthKey: "parse_hash")
        let parseNode = TrunkNode(
            id: "parse",
            coordinate: parseCoord,
            channels: [
                TrunkChannel(index: 0, language: "rosetta", content: "func parseInput/1"),
                TrunkChannel(index: 1, language: "swift", content: "func parseInput(raw: String) -> Int { 0 }")
            ]
        )
        trunk.add(parseNode)

        let bridge = TrunkBridge(edges: [
            TrunkEdge(source: "calc", target: "format", kind: .call)
        ])

        return (trunk, bridge)
    }

    @Test func queryNamingAFunctionScoresItTop() {
        let (trunk, bridge) = makeTrunk()
        let results = ContextRetriever.retrieve(query: "how does calculateTotal work?", trunk: trunk, bridge: bridge, limit: 8)

        #expect(!results.isEmpty)
        #expect(results.first?.node.id == "calc")
        #expect(results.first?.matchedDirectly == true)
    }

    @Test func bridgeExpansionPullsInCallee() {
        let (trunk, bridge) = makeTrunk()
        let results = ContextRetriever.retrieve(query: "calculateTotal", trunk: trunk, bridge: bridge, limit: 8)

        // formatCurrency isn't named in the query, but calc calls it — it
        // should be pulled in by the one-hop bridge expansion.
        #expect(results.contains { $0.node.id == "format" && $0.matchedDirectly == false })
        // parseInput is unrelated and not called by calc — should not appear.
        #expect(!results.contains { $0.node.id == "parse" })
    }

    @Test func noBridgeMeansNoExpansion() {
        let (trunk, _) = makeTrunk()
        let results = ContextRetriever.retrieve(query: "calculateTotal", trunk: trunk, bridge: nil, limit: 8)

        #expect(results.count == 1)
        #expect(results.first?.node.id == "calc")
    }

    @Test func unrelatedQueryMatchesUnrelatedFunction() {
        let (trunk, bridge) = makeTrunk()
        let results = ContextRetriever.retrieve(query: "parseInput", trunk: trunk, bridge: bridge, limit: 8)

        #expect(results.first?.node.id == "parse")
        // parseInput has no outgoing edges, so no expansion nodes appear.
        #expect(results.count == 1)
    }

    @Test func queryWithNoMatchesReturnsEmpty() {
        let (trunk, bridge) = makeTrunk()
        let results = ContextRetriever.retrieve(query: "nonexistentZzyzx", trunk: trunk, bridge: bridge, limit: 8)
        #expect(results.isEmpty)
    }

    @Test func emptyQueryReturnsEmpty() {
        let (trunk, bridge) = makeTrunk()
        let results = ContextRetriever.retrieve(query: "   ", trunk: trunk, bridge: bridge, limit: 8)
        #expect(results.isEmpty)
    }

    @Test func limitCapsDirectMatchesButNotExpansion() {
        let (trunk, bridge) = makeTrunk()
        // Both calc and format mention "currency"/"total" style terms via
        // shared query tokens; force limit=1 and confirm only 1 direct match
        // survives, though expansion can still add more.
        let results = ContextRetriever.retrieve(query: "calculateTotal formatCurrency", trunk: trunk, bridge: bridge, limit: 1)
        let direct = results.filter { $0.matchedDirectly }
        #expect(direct.count == 1)
    }

    @Test func zeroLimitReturnsEmpty() {
        let (trunk, bridge) = makeTrunk()
        let results = ContextRetriever.retrieve(query: "calculateTotal", trunk: trunk, bridge: bridge, limit: 0)
        #expect(results.isEmpty)
    }

    @Test func tokenizeLowercasesAndSplitsOnNonAlphanumerics() {
        let tokens = ContextRetriever.tokenize("How-does_calculateTotal Work?!")
        #expect(tokens == ["how", "does", "calculatetotal", "work"])
    }

    @Test func scoreIsHigherWithMoreOverlappingTerms() {
        let (trunk, bridge) = makeTrunk()
        let results = ContextRetriever.retrieve(query: "func calculateTotal", trunk: trunk, bridge: bridge, limit: 8)
        // "func" appears in kind for ALL nodes, "calculatetotal" only in calc's
        // name/skeleton — calc should score at least as high as any other
        // direct match and be first among direct matches.
        let firstDirect = results.first { $0.matchedDirectly }
        #expect(firstDirect?.node.id == "calc")
    }
}
