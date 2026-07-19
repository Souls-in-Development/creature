// Workspace-grounding for a chat session: keep a live index of a directory,
// detect when it goes stale, and turn a user message into a "relevant code
// context" block retrieved from the trunk.
//
// Unlike the version this replaces (which lived in the CLI and printed ANSI
// progress lines inline), nothing here prints. Staleness and cache state are
// returned as values; the caller decides whether to show them.

import Foundation
import CreatureTrunk
import CreatureWorkspace

/// A single turn in the chat history, folded back into the prompt each turn so
/// the conversation is multi-turn rather than stateless.
struct ChatTurn {
    let user: String
    let reply: String
}

/// Builds a single prompt string carrying prior turns plus the new user message,
/// so a partner with no native multi-turn API (HTTPPartner/EmbeddedPartner both
/// take one `prompt` string) still sees history.
func foldHistory(_ history: [ChatTurn], newMessage: String) -> String {
    guard !history.isEmpty else { return newMessage }

    var lines: [String] = []
    for turn in history {
        lines.append("User: \(turn.user)")
        lines.append("Assistant: \(turn.reply)")
    }
    lines.append("User: \(newMessage)")
    return lines.joined(separator: "\n\n")
}

let chatSystemPrompt = """
You are the creature — a living terminal having an ongoing conversation. \
Prior turns are included as context. Be concise and direct. When asked for \
code, return only the code unless an explanation is explicitly requested.
"""

/// Assemble the "Relevant code context" block from retrieval results, capped at
/// `ContextDefaults.blockCharBudget`. Public because the CLI's `ask --context`
/// path uses it directly, not only the chat engine.
public func buildContextBlock(results: [ContextRetriever.Result]) -> (block: String, includedPaths: [String]) {
    guard !results.isEmpty else { return ("", []) }

    var lines: [String] = ["Relevant code context (retrieved, not exhaustive):"]
    var includedPaths: [String] = []
    var used = 0

    for result in results {
        let node = result.node
        let snippet = node.channel(at: 1)?.content ?? node.truthChannel?.content ?? ""
        let entry = "\n--- \(node.coordinate.pathKey) (\(node.coordinate.kind)) ---\n\(snippet)"
        guard used + entry.count <= ContextDefaults.blockCharBudget else { break }
        lines.append(entry)
        includedPaths.append(node.coordinate.pathKey)
        used += entry.count
    }

    return (lines.joined(separator: "\n"), includedPaths)
}

/// Holds the live, mutable workspace-awareness state for a context-grounded chat
/// session: the current index (trunk + bridge) and the watcher tracking whether
/// it has gone stale. Re-indexing (staleness- or user-triggered) replaces
/// `workspace` and resets `watcher`'s baseline in one place.
struct ChatContextSession {
    let directory: String
    private(set) var workspace: WorkspaceIndexer.Workspace
    private(set) var watcher: WorkspaceWatcher

    /// True when the initial index was served from a fresh on-disk snapshot
    /// rather than a full re-index. The caller may surface this; the engine does
    /// not print it.
    let loadedFromCache: Bool

    init(directory: String) {
        self.directory = directory

        var ws: WorkspaceIndexer.Workspace
        var warnings: [String] = []
        var fromCache = false
        if let snapshot = WorkspaceIndexer.loadSnapshot(for: directory, warnings: &warnings),
           !WorkspaceIndexer.isSnapshotStale(snapshot, for: directory) {
            ws = WorkspaceIndexer.workspace(from: snapshot)
            fromCache = true
        } else {
            let fresh = WorkspaceIndexer.index(directory: directory)
            ws = fresh
            let treeIndex = TreeIndex.from(nodes: fresh.trunk.nodes)
            let snapshot = CompletionTreeSnapshot(
                nodes: fresh.trunk.nodes,
                treeIndex: treeIndex,
                leafStatus: [:],
                rolledUpStatus: [:],
                bridge: fresh.bridge
            )
            try? WorkspaceIndexer.saveSnapshot(snapshot, for: directory)
        }
        self.workspace = ws
        self.loadedFromCache = fromCache
        self.watcher = WorkspaceWatcher(directory: directory)
    }

    /// Re-index the whole workspace (v0: whole-workspace, not per-file
    /// incremental — see `WorkspaceWatcher`) and reset the staleness baseline to
    /// the freshly-indexed state.
    mutating func reindex() {
        let ws = WorkspaceIndexer.index(directory: directory)
        workspace = ws
        let treeIndex = TreeIndex.from(nodes: ws.trunk.nodes)
        let snapshot = CompletionTreeSnapshot(
            nodes: ws.trunk.nodes,
            treeIndex: treeIndex,
            leafStatus: [:],
            rolledUpStatus: [:],
            bridge: ws.bridge
        )
        try? WorkspaceIndexer.saveSnapshot(snapshot, for: directory)
        watcher.refresh()
    }

    /// Per-turn context step: check staleness first (re-indexing if anything
    /// changed), then retrieve nodes relevant to `input` and build the same
    /// "Relevant code context:" block `ask --context` uses.
    ///
    /// - Returns: the block text (empty when nothing matched), the node paths
    ///   included, and how many files changed since the last turn (0 unless a
    ///   re-index was triggered) — so the caller can report a re-index without
    ///   this type having to print.
    mutating func turnContext(for input: String) -> (prefix: String, paths: [String], reindexedCount: Int) {
        let changes = watcher.detectChanges()
        let reindexedCount = changes.count
        if !changes.isEmpty {
            reindex()
        }

        let results = ContextRetriever.retrieve(
            query: input,
            trunk: workspace.trunk,
            bridge: workspace.bridge,
            limit: ContextDefaults.contextLimit
        )

        let (block, paths) = buildContextBlock(results: results)
        guard !block.isEmpty else { return ("", [], reindexedCount) }
        return (block + "\n\n", paths, reindexedCount)
    }
}
