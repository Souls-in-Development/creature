// LearnedNodeClassifications — the gap-fill-and-learn store for trunk node
// domain classification.
//
// Foundation (Apple's on-device model) acts as an internal, never-user-facing
// "connection oracle" for the tentacles too, exactly as it does for routing
// (see `CreatureInference/LearnedRouting.swift`): the FIRST time the trunk
// meets a node whose Channel-0 structural skeleton it hasn't seen before
// (identified by `TrunkCoordinate.truthKey`), it asks Foundation to classify
// that node's domain + summarize it. That decision is written here, keyed by
// `truthKey`, so every subsequent node sharing the same skeleton is
// classified instantly from disk — no Foundation call, no oracle, just a
// learned fact.
//
// Keying by `truthKey` (not by node id or path) is deliberate: it's the same
// mechanism `CodeTrunk.nodesSharing(truthKey:)` uses for cross-language
// equivalence, so two nodes with identical Channel-0 skeletons (same
// declaration shape, possibly in different files or languages) share one
// classification rather than re-asking Foundation for each occurrence.
//
// This is a separate store from `LearnedRouting` (different axis — node
// domain vs. prompt routing) and from `SyncProfile` (partner calibration
// weights), kept in its own file at `~/.creature/node-classifications.json`.

import Foundation
import CreatureTrunk

/// Persisted map of `truthKey` -> learned node classification. Lives at
/// `~/.creature/node-classifications.json`, independent of `LearnedRouting`
/// and `SyncProfile`.
public struct LearnedNodeClassifications: Sendable, Codable {
    public var classifications: [String: NodeClassificationResult]

    public static let defaultPath = "\(NSHomeDirectory())/.creature/node-classifications.json"

    public init(classifications: [String: NodeClassificationResult] = [:]) {
        self.classifications = classifications
    }

    /// Look up a previously learned classification for a `truthKey`.
    public func classification(for truthKey: String) -> NodeClassificationResult? {
        classifications[truthKey]
    }

    /// Record (or overwrite) a classification for a `truthKey`.
    public mutating func learn(truthKey: String, classification: NodeClassificationResult) {
        classifications[truthKey] = classification
    }

    /// Load from disk. Returns an empty store if the file doesn't exist yet
    /// or fails to decode — a fresh/missing classifications file is not an
    /// error, it just means nothing has been learned yet.
    public static func load(from path: String = LearnedNodeClassifications.defaultPath) -> LearnedNodeClassifications {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return LearnedNodeClassifications()
        }
        guard let decoded = try? JSONDecoder().decode(LearnedNodeClassifications.self, from: data) else {
            return LearnedNodeClassifications()
        }
        return decoded
    }

    /// Persist to disk, creating `~/.creature/` if needed.
    public func save(to path: String = LearnedNodeClassifications.defaultPath) throws {
        let dir = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: URL(fileURLWithPath: path))
    }
}

/// Outcome of classifying a whole trunk: every node's classification (from
/// cache or freshly oracle-filled), plus counters so callers can report the
/// oracle→cache split honestly.
public struct TrunkClassificationOutcome: Sendable {
    public let classifications: [String: NodeClassificationResult]
    public let oracleCalls: Int
    public let cacheHits: Int

    public init(classifications: [String: NodeClassificationResult], oracleCalls: Int, cacheHits: Int) {
        self.classifications = classifications
        self.oracleCalls = oracleCalls
        self.cacheHits = cacheHits
    }
}

/// Gap-fill-and-learn classification over a whole trunk: for each node,
/// HIT if its `truthKey` is already cached in `~/.creature/node-classifications.json`
/// (used with no Foundation call), GAP if not (Foundation is consulted,
/// the result is cached and persisted, and counted as an oracle call).
///
/// Foundation fires only on genuinely novel skeletons — a file with N nodes
/// sharing the same `truthKey` (e.g. repeated boilerplate) pays for at most
/// one oracle call, not N. When Foundation itself is unavailable, nodes with
/// no cached entry are simply left unclassified (no entry in the returned
/// map) rather than guessed at — the caller is expected to check
/// `foundationUnavailableReason()` up front and print that instead of
/// attempting this at all (see `cmdClassify` in CreatureCLI).
///
/// - Parameter trunk: the trunk to classify.
/// - Parameter store: the learned-classifications store to read/write.
///   Defaults to loading from disk; passed explicitly so tests can exercise
///   the cache round-trip without touching `~/.creature/`.
/// - Parameter path: where to persist newly-learned classifications.
public func classify(
    trunk: CodeTrunk,
    store: LearnedNodeClassifications = LearnedNodeClassifications.load(),
    path: String = LearnedNodeClassifications.defaultPath
) async -> TrunkClassificationOutcome {
    var learned = store
    var result: [String: NodeClassificationResult] = [:]
    var oracleCalls = 0
    var cacheHits = 0
    var didLearnAnything = false

    for node in trunk.nodes {
        let truthKey = node.coordinate.truthKey

        // Multiple nodes can share a truthKey (see CodeTrunk.nodesSharing) —
        // if this run already resolved it (from cache or a prior oracle call
        // in this same loop), reuse it without counting it again.
        if let already = result[truthKey] {
            result[truthKey] = already
            continue
        }

        if let cached = learned.classification(for: truthKey) {
            result[truthKey] = cached
            cacheHits += 1
            continue
        }

        let skeleton = node.truthChannel?.content ?? truthKey
        let source = node.channels.first { $0.index != 0 }?.content ?? skeleton

        if let filled = await classifyIfAvailable(skeleton: skeleton, source: source) {
            result[truthKey] = filled
            learned.learn(truthKey: truthKey, classification: filled)
            oracleCalls += 1
            didLearnAnything = true
        }
    }

    if didLearnAnything {
        try? learned.save(to: path)
    }

    return TrunkClassificationOutcome(classifications: result, oracleCalls: oracleCalls, cacheHits: cacheHits)
}
