import Foundation

/// Retrieval over the trunk: given a natural-language query, find the
/// `TrunkNode`s most likely relevant to it. This is the piece that turns the
/// trunk from "a thing you can index and inspect" into "context you can feed
/// an LLM" (see
/// `docs/plans/2026-07-05-creature-cursor-competitor-architecture.md` §Build
/// log "Next" #3, "wire the context into `chat`/`ask`").
///
/// HONEST SCOPE (v0): this is **keyword overlap + one Bridge hop**, not
/// semantic retrieval. There is no embedding model, no vector index, no
/// learned relevance signal here — a query and a node "match" only if they
/// share literal (lowercased, alphanumeric-tokenized) terms in the node's
/// name, path, kind, or Channel-0 skeleton. That is a real, useful mechanism
/// (it is exactly how a human greps a codebase) but it is not semantic
/// understanding: a query for "authentication" will not find a node named
/// `checkCredentials` unless the token "credentials" or "auth" literally
/// appears somewhere the scorer looks. Semantic/embedding-based retrieval is
/// future work — see the architecture doc's Foundation-assist precedent for
/// how a gap-fill oracle could eventually extend this without replacing it.
public enum ContextRetriever {

    /// One scored retrieval result: a node plus the score that ranked it and
    /// whether it was pulled in directly (matched the query) or added by the
    /// one-hop Bridge expansion (a callee of a directly-matched node).
    public struct Result: Sendable {
        public let node: TrunkNode
        public let score: Int
        public let matchedDirectly: Bool

        public init(node: TrunkNode, score: Int, matchedDirectly: Bool) {
            self.node = node
            self.score = score
            self.matchedDirectly = matchedDirectly
        }
    }

    /// Retrieve the nodes most relevant to `query` from `trunk`.
    ///
    /// Scoring (v0, per node):
    ///   - tokenize `query` on non-alphanumeric boundaries, lowercased;
    ///   - tokenize the node's last path segment (its "name"), full dotted
    ///     `pathKey`, `kind`, and Channel-0 content the same way;
    ///   - score = count of query tokens that appear in that combined token
    ///     set (each matching query token counts once per node, not once per
    ///     occurrence — this keeps the score bounded by query length and easy
    ///     to reason about).
    ///
    /// Nodes with a score of 0 are dropped entirely (no match at all is not
    /// "relevant, just barely" — it's irrelevant). The remaining nodes are
    /// sorted by score descending; ties are broken **stably** by each node's
    /// original position in `trunk.nodes` (Swift's `sorted(by:)` is not
    /// guaranteed stable, so ties are broken explicitly by recorded index
    /// rather than relying on sort stability).
    ///
    /// After the top `limit` direct matches are chosen, the result is
    /// **expanded by one Bridge hop**: for every directly-matched node, every
    /// node it calls (`bridge.targets(of:)`) is added too, if not already
    /// present — "a question about a caller wants its callees too." Expansion
    /// nodes are appended after the direct matches, in the order their source
    /// match was encountered, and are marked `matchedDirectly == false`. When
    /// `bridge` is `nil`, no expansion happens (direct matches only).
    ///
    /// - Parameters:
    ///   - query: free-text question or search string.
    ///   - trunk: the indexed codebase to search.
    ///   - bridge: optional call graph for one-hop expansion.
    ///   - limit: maximum number of *directly matched* nodes to keep before
    ///     expansion (expansion nodes are additional, not counted against
    ///     this cap — the cap governs relevance breadth, not final context
    ///     size, which callers should budget separately, e.g. by character
    ///     count of the snippets they actually send to an LLM).
    public static func retrieve(
        query: String,
        trunk: CodeTrunk,
        bridge: TrunkBridge? = nil,
        limit: Int
    ) -> [Result] {
        guard limit > 0 else { return [] }

        let queryTokens = Set(tokenize(query))
        guard !queryTokens.isEmpty else { return [] }

        var scored: [(index: Int, node: TrunkNode, score: Int)] = []
        for (index, node) in trunk.nodes.enumerated() {
            let score = overlapScore(queryTokens: queryTokens, node: node)
            guard score > 0 else { continue }
            scored.append((index, node, score))
        }

        // Sort by score descending; break ties by original trunk order
        // (explicit index comparison — stable regardless of sort algorithm).
        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.index < rhs.index
        }

        let topDirect = scored.prefix(limit)
        var results: [Result] = topDirect.map { Result(node: $0.node, score: $0.score, matchedDirectly: true) }

        guard let bridge else { return results }

        var seenIDs = Set(results.map { $0.node.id })
        var expansions: [Result] = []
        for match in topDirect {
            for targetID in bridge.targets(of: match.node.id) {
                guard !seenIDs.contains(targetID) else { continue }
                guard let targetNode = trunk.node(id: targetID) else { continue }
                seenIDs.insert(targetID)
                expansions.append(Result(node: targetNode, score: 0, matchedDirectly: false))
            }
        }

        results.append(contentsOf: expansions)
        return results
    }

    /// Count of query tokens present in this node's searchable token set
    /// (name, full path, kind, Channel-0 skeleton). Bounded by
    /// `queryTokens.count` — repeated occurrences of the same term don't
    /// inflate the score.
    private static func overlapScore(queryTokens: Set<String>, node: TrunkNode) -> Int {
        var nodeTokens = Set<String>()
        if let name = node.coordinate.path.last {
            nodeTokens.formUnion(tokenize(name))
        }
        nodeTokens.formUnion(tokenize(node.coordinate.pathKey))
        nodeTokens.formUnion(tokenize(node.coordinate.kind))
        if let skeleton = node.truthChannel?.content {
            nodeTokens.formUnion(tokenize(skeleton))
        }
        return queryTokens.intersection(nodeTokens).count
    }

    /// Lowercase, tokenize on runs of non-alphanumeric characters. Shared by
    /// both the query and every node field scored against it, so "the same
    /// word" always tokenizes identically regardless of which side it came
    /// from (e.g. camelCase `calculateTotal` and free text "calculate total"
    /// both yield the same two tokens after splitting on non-alphanumerics —
    /// camelCase boundaries themselves are NOT split, only non-alphanumeric
    /// separators are; that's an honest v0 limit, not an oversight).
    static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
