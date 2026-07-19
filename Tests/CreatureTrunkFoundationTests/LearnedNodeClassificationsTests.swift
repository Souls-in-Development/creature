import Testing
import Foundation
@testable import CreatureTrunkFoundation
import CreatureTrunk

/// Offline-safe tests: exercise the cache round-trip and the classify(trunk:)
/// gap-fill-and-learn bookkeeping without requiring a live Foundation call.
/// `classify(trunk:)` degrades to "unclassified, zero oracle calls" whenever
/// Foundation itself is unavailable (pre-macOS 26, ineligible hardware, Apple
/// Intelligence off, or CI without it enabled) — exactly like
/// `classifyRouteIfAvailable` does for routing — so these tests assert on
/// that degrade path plus the parts that don't touch the model at all: cache
/// hit/miss bookkeeping, persistence, and truthKey-sharing dedup.
@Suite struct LearnedNodeClassificationsTests {

    @Test func emptyStoreHasNoClassification() {
        let store = LearnedNodeClassifications()
        #expect(store.classification(for: "abc123") == nil)
    }

    @Test func learnAndLookup() {
        var store = LearnedNodeClassifications()
        let result = NodeClassificationResult(domain: "networking", summary: "Fetches a URL.")
        store.learn(truthKey: "abc123", classification: result)
        #expect(store.classification(for: "abc123") == result)
    }

    @Test func learnOverwritesExistingEntry() {
        var store = LearnedNodeClassifications()
        store.learn(truthKey: "k", classification: NodeClassificationResult(domain: "general", summary: "first"))
        store.learn(truthKey: "k", classification: NodeClassificationResult(domain: "crypto", summary: "second"))
        #expect(store.classification(for: "k")?.domain == "crypto")
        #expect(store.classification(for: "k")?.summary == "second")
    }

    @Test func codableRoundTrip() throws {
        var store = LearnedNodeClassifications()
        store.learn(truthKey: "k1", classification: NodeClassificationResult(domain: "persistence", summary: "Saves to disk."))
        store.learn(truthKey: "k2", classification: NodeClassificationResult(domain: "ui", summary: "Renders a view."))

        let data = try JSONEncoder().encode(store)
        let decoded = try JSONDecoder().decode(LearnedNodeClassifications.self, from: data)

        #expect(decoded.classification(for: "k1")?.domain == "persistence")
        #expect(decoded.classification(for: "k2")?.summary == "Renders a view.")
    }

    @Test func loadFromMissingPathReturnsEmptyStore() {
        let missingPath = "/tmp/creature-node-classifications-\(UUID().uuidString)-does-not-exist.json"
        let store = LearnedNodeClassifications.load(from: missingPath)
        #expect(store.classifications.isEmpty)
    }

    @Test func saveThenLoadRoundTrips() throws {
        let path = "/tmp/creature-node-classifications-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: path) }

        var store = LearnedNodeClassifications()
        store.learn(truthKey: "func hash/1", classification: NodeClassificationResult(domain: "crypto", summary: "Hashes input."))
        try store.save(to: path)

        let loaded = LearnedNodeClassifications.load(from: path)
        #expect(loaded.classification(for: "func hash/1")?.domain == "crypto")
    }

    @Test func saveCreatesIntermediateDirectories() throws {
        let dir = "/tmp/creature-node-classify-test-\(UUID().uuidString)"
        let path = "\(dir)/nested/node-classifications.json"
        defer { try? FileManager.default.removeItem(atPath: dir) }

        var store = LearnedNodeClassifications()
        store.learn(truthKey: "k", classification: NodeClassificationResult(domain: "testing", summary: "A test."))
        try store.save(to: path)

        #expect(FileManager.default.fileExists(atPath: path))
    }

    // MARK: - classify(trunk:) gap-fill-and-learn bookkeeping

    private func makeNode(id: String, path: [String], truthKey: String, skeleton: String, source: String) -> TrunkNode {
        TrunkNode(
            id: id,
            coordinate: TrunkCoordinate(path: path, kind: "func", truthKey: truthKey),
            channels: [
                TrunkChannel(index: 0, language: "rosetta", content: skeleton),
                TrunkChannel(index: 1, language: "swift", content: source)
            ]
        )
    }

    @Test func classifyUsesCacheWithoutOracleCallsWhenAllTruthKeysCached() async {
        var trunk = CodeTrunk()
        trunk.add(makeNode(id: "1", path: ["M", "fetch"], truthKey: "k1", skeleton: "func fetch/0", source: "func fetch() {}"))
        trunk.add(makeNode(id: "2", path: ["M", "save"], truthKey: "k2", skeleton: "func save/0", source: "func save() {}"))

        var store = LearnedNodeClassifications()
        store.learn(truthKey: "k1", classification: NodeClassificationResult(domain: "networking", summary: "Fetches data."))
        store.learn(truthKey: "k2", classification: NodeClassificationResult(domain: "persistence", summary: "Saves data."))

        let scratchPath = "/tmp/creature-node-classify-cache-only-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: scratchPath) }

        let outcome = await classify(trunk: trunk, store: store, path: scratchPath)

        #expect(outcome.cacheHits == 2)
        #expect(outcome.oracleCalls == 0)
        #expect(outcome.classifications["k1"]?.domain == "networking")
        #expect(outcome.classifications["k2"]?.domain == "persistence")
        // Nothing new was learned, so no file should have been written.
        #expect(!FileManager.default.fileExists(atPath: scratchPath))
    }

    @Test func classifySharesResultAcrossNodesWithSameTruthKey() async {
        var trunk = CodeTrunk()
        // Two nodes, same truthKey (e.g. identical skeleton in two files) —
        // should resolve to the same cached classification and count as one
        // cache hit conceptually reused, not re-queried.
        trunk.add(makeNode(id: "1", path: ["A", "helper"], truthKey: "shared", skeleton: "func helper/0", source: "func helper() {}"))
        trunk.add(makeNode(id: "2", path: ["B", "helper"], truthKey: "shared", skeleton: "func helper/0", source: "func helper() {}"))

        var store = LearnedNodeClassifications()
        store.learn(truthKey: "shared", classification: NodeClassificationResult(domain: "general", summary: "A helper."))

        let outcome = await classify(trunk: trunk, store: store, path: "/tmp/creature-unused-\(UUID().uuidString).json")

        #expect(outcome.classifications.count == 1)
        #expect(outcome.classifications["shared"]?.domain == "general")
        #expect(outcome.oracleCalls == 0)
    }

    @Test func classifyOnEmptyTrunkProducesNoCallsAndNoWrite() async {
        let trunk = CodeTrunk()
        let scratchPath = "/tmp/creature-node-classify-empty-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: scratchPath) }

        let outcome = await classify(trunk: trunk, store: LearnedNodeClassifications(), path: scratchPath)

        #expect(outcome.classifications.isEmpty)
        #expect(outcome.oracleCalls == 0)
        #expect(outcome.cacheHits == 0)
        #expect(!FileManager.default.fileExists(atPath: scratchPath))
    }

    /// When a truthKey is NOT cached and Foundation is unavailable (the
    /// common CI/offline case — see `classifyIfAvailable`'s doc comment),
    /// the node is left out of the result map entirely rather than guessed
    /// at. This only asserts the degrade behavior actually holds when
    /// Foundation is unavailable; on a machine where Apple Intelligence IS
    /// enabled this test still passes because a genuinely uncached node
    /// would either classify (and this assertion about the *unavailable*
    /// path doesn't apply) or the environment check below skips it.
    @Test func classifyLeavesUncachedNodeUnresolvedWhenFoundationUnavailable() async {
        guard foundationUnavailableReason() != nil else {
            // Foundation is actually available on this machine — this test
            // is specifically about the unavailable-degrade path, so skip
            // rather than making a live oracle call from a unit test.
            return
        }

        var trunk = CodeTrunk()
        trunk.add(makeNode(id: "1", path: ["M", "mystery"], truthKey: "uncached-key", skeleton: "func mystery/0", source: "func mystery() {}"))

        let scratchPath = "/tmp/creature-node-classify-unavailable-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: scratchPath) }

        let outcome = await classify(trunk: trunk, store: LearnedNodeClassifications(), path: scratchPath)

        #expect(outcome.classifications["uncached-key"] == nil)
        #expect(outcome.oracleCalls == 0)
        #expect(outcome.cacheHits == 0)
    }
}

@Suite struct CodeDomainTests {
    @Test func domainVocabularyIsFixedAndNonEmpty() {
        #expect(!CodeDomain.all.isEmpty)
        #expect(CodeDomain.all.contains("general"))
        #expect(CodeDomain.all.contains("networking"))
        #expect(CodeDomain.all.contains("crypto"))
    }
}
