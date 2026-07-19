// ChatEngine — the headless, multi-turn chat pipeline.
//
// Construct it once (loads the two partners, the sync profile, and any workspace
// context), then call `send` per user message. It is an actor so its history and
// context state stay consistent whether it is driven by the CLI's single-threaded
// REPL or the IDE's concurrent SwiftUI tasks.

import Foundation
import CreatureSpine
import CreatureInference

/// Curated default MLX souls per slot (see RELEASE_PLAN.md "Model management").
/// 3B pair: resident-safe on 8GB Apple Silicon, Apache-2.0, shared Qwen2.5
/// tokenizer.
public let defaultConsciousLocalModel = "mlx-community/Qwen2.5-3B-Instruct-4bit"
public let defaultUnconsciousLocalModel = "mlx-community/Qwen2.5-Coder-3B-Instruct-4bit"

extension CreatureConfig {
    /// A zero-setup config that runs both slots in-process on the default local
    /// souls — what the IDE (and a fresh CLI) fall back to when the user has not
    /// run `creature config`. First message downloads the model, exactly like
    /// `creature local`.
    public static var defaultLocal: CreatureConfig {
        CreatureConfig(
            consciousURL: SlotProvider.local(modelId: defaultConsciousLocalModel).configValue,
            consciousKey: "",
            consciousModel: defaultConsciousLocalModel,
            unconsciousURL: SlotProvider.local(modelId: defaultUnconsciousLocalModel).configValue,
            unconsciousKey: "",
            unconsciousModel: defaultUnconsciousLocalModel,
            profilePath: CreatureConfig.defaultProfilePath
        )
    }
}

public actor ChatEngine {
    /// One model-generation result, everything a surface needs to render a turn
    /// without reaching back into the pipeline. No ANSI, no formatting.
    public struct Reply: Sendable {
        public let text: String
        public let role: PartnerRole
        /// True when both slots ran and were synthesized, so naming a single role
        /// would be a lie — render "coordinated" instead.
        public let isCoordinated: Bool
        public let latencyMs: Double
        public let confidence: Float
        /// Trunk node paths retrieved as grounding for this turn (empty without a
        /// context directory, or when nothing matched).
        public let contextPaths: [String]
        /// Files changed since the previous turn that forced a re-index (0 unless
        /// the workspace went stale).
        public let reindexedCount: Int
        public let isSuccess: Bool
        public let errorDescription: String?
    }

    private let orchestrator: TerminalOrchestrator
    private var history: [ChatTurn] = []
    private var contextSession: ChatContextSession?

    /// File / node counts of the indexed context directory, for a caller that
    /// wants to report "indexed N files" — nil when no context directory.
    public let contextFileCount: Int?
    public let contextNodeCount: Int?
    public let loadedContextFromCache: Bool

    /// Whether indexing the context directory hit its caps. Surfaced (not
    /// swallowed) so a caller can warn that the workspace was scanned only
    /// partially — a silent partial index would answer confidently over a
    /// fraction of the code. All false without a context directory.
    public let contextHitFileCap: Bool
    public let contextHitByteCap: Bool
    public let contextSkippedLargeFileCount: Int

    /// - Parameters:
    ///   - config: the two slots to run. Use `CreatureConfig.load()` for the
    ///     user's configured pair, or `.defaultLocal` for zero-setup local souls.
    ///   - contextDirectory: a workspace to ground every turn in, or nil for
    ///     plain conversation.
    ///   - onModelProgress: model-load / download progress per slot (fraction in
    ///     0...1). Fired on a background context; hop to the main actor before
    ///     touching UI.
    public init(
        config: CreatureConfig,
        contextDirectory: String? = nil,
        onModelProgress: (@Sendable (PartnerRole, Double) -> Void)? = nil
    ) {
        let conscious = makePartner(
            url: config.consciousURL,
            key: config.consciousKey,
            model: config.consciousModel,
            role: .conscious,
            onProgress: onModelProgress.map { cb -> @Sendable (Double) -> Void in
                { (fraction: Double) in cb(.conscious, fraction) }
            }
        )
        let unconscious = makePartner(
            url: config.unconsciousURL,
            key: config.unconsciousKey,
            model: config.unconsciousModel,
            role: .unconscious,
            onProgress: onModelProgress.map { cb -> @Sendable (Double) -> Void in
                { (fraction: Double) in cb(.unconscious, fraction) }
            }
        )

        // A sync profile enables trained routing weights; without one, fall back
        // to a neutral 50/50 profile so chat still works pre-calibration.
        let profile = (try? SyncProfile.load(from: URL(fileURLWithPath: config.profilePath))) ?? SyncProfile(
            partnerA: conscious.metadata,
            partnerB: unconscious.metadata,
            roleA: .conscious,
            roleB: .unconscious,
            confidenceConscious: 0.5,
            confidenceUnconscious: 0.5,
            latencyDeltaMs: 0,
            isInSync: false,
            consciousWeightA: 1.0,
            unconsciousWeightA: 0.0,
            testCount: 0
        )

        self.orchestrator = TerminalOrchestrator(partnerA: conscious, partnerB: unconscious, profile: profile)

        if let contextDirectory {
            let session = ChatContextSession(directory: contextDirectory)
            self.contextSession = session
            self.contextFileCount = session.workspace.fileCount
            self.contextNodeCount = session.workspace.trunk.nodes.count
            self.loadedContextFromCache = session.loadedFromCache
            self.contextHitFileCap = session.workspace.hitFileCap
            self.contextHitByteCap = session.workspace.hitByteCap
            self.contextSkippedLargeFileCount = session.workspace.skippedLargeFiles.count
        } else {
            self.contextSession = nil
            self.contextFileCount = nil
            self.contextNodeCount = nil
            self.loadedContextFromCache = false
            self.contextHitFileCap = false
            self.contextHitByteCap = false
            self.contextSkippedLargeFileCount = 0
        }
    }

    /// Force a re-index of the context directory. No-op (returns 0) without one.
    /// - Returns: the file count after re-indexing.
    @discardableResult
    public func reindex() -> Int {
        guard contextSession != nil else { return 0 }
        contextSession?.reindex()
        return contextSession?.workspace.fileCount ?? 0
    }

    /// Send one user message and get the model's reply. Folds prior turns in,
    /// grounds the turn in retrieved workspace context (if any), routes to a
    /// slot, and records the exchange in history on success.
    public func send(_ message: String) async -> Reply {
        var contextPrefix = ""
        var contextPaths: [String] = []
        var reindexedCount = 0
        if contextSession != nil {
            let turn = contextSession!.turnContext(for: message)
            contextPrefix = turn.prefix
            contextPaths = turn.paths
            reindexedCount = turn.reindexedCount
        }

        let folded = foldHistory(history, newMessage: message)
        let task = TerminalTask(
            prompt: contextPrefix + folded,
            systemPrompt: groundedSystem(chatSystemPrompt, prompt: message),
            preferredRole: await resolveRoute(for: message)
        )

        let result = await orchestrator.execute(task: task)

        guard result.isSuccess else {
            return Reply(
                text: "",
                role: result.fromRole,
                isCoordinated: result.isCoordinated,
                latencyMs: result.latencyMs,
                confidence: result.confidence,
                contextPaths: contextPaths,
                reindexedCount: reindexedCount,
                isSuccess: false,
                errorDescription: result.error?.localizedDescription ?? "unknown"
            )
        }

        history.append(ChatTurn(user: message, reply: result.response))
        return Reply(
            text: result.response,
            role: result.fromRole,
            isCoordinated: result.isCoordinated,
            latencyMs: result.latencyMs,
            confidence: result.confidence,
            contextPaths: contextPaths,
            reindexedCount: reindexedCount,
            isSuccess: true,
            errorDescription: nil
        )
    }
}
