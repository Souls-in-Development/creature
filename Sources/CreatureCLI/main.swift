// Creature CLI — A living terminal. soulsin.dev
//
// Usage:
//   creature calibrate --conscious <api-url> --unconscious <api-url>
//   creature run [--profile <path>]
//   creature status
//
// The vessel before the soul.

import Foundation
import CreatureSpine
import CreatureInference
import CreatureTrunk
import CreatureTrunkSwift
import CreatureTrunkPython
import CreatureTrunkFoundation
import CreatureSnippets
import CreatureKeys
import CreatureWorkspace
import CreatureChat

// MARK: - ANSI helpers

enum ANSI {
    static let reset   = "\u{1B}[0m"
    static let bold    = "\u{1B}[1m"
    static let dim     = "\u{1B}[2m"
    static let teal    = "\u{1B}[38;5;115m"
    static let amber   = "\u{1B}[38;5;215m"
    static let pink    = "\u{1B}[38;5;211m"
    static let blue    = "\u{1B}[38;5;111m"
    static let purple  = "\u{1B}[38;5;141m"
    static let gray    = "\u{1B}[38;5;243m"
    static let white   = "\u{1B}[38;5;253m"
}


// MARK: - Commands

func printBanner() {
    print("""

    \(ANSI.teal)C R E A T U R E\(ANSI.reset)
    \(ANSI.gray)A living terminal  ·  soulsin.dev\(ANSI.reset)

    """)
}

func printUsage() {
    printBanner()
    print("""
    \(ANSI.white)Usage:\(ANSI.reset)
      \(ANSI.teal)creature calibrate\(ANSI.reset)   Run the sync handshake between two LLMs
      \(ANSI.teal)creature config\(ANSI.reset)       Set up LLM endpoints
      \(ANSI.teal)creature status\(ANSI.reset)       Show current sync profile
      \(ANSI.teal)creature ask\(ANSI.reset) <prompt>  Ask the creature something
      \(ANSI.teal)creature chat\(ANSI.reset)         Persistent multi-turn conversation (Ctrl-D or :quit to exit)
      \(ANSI.teal)creature chat --context\(ANSI.reset) <dir>  Chat grounded in a workspace, re-indexed on file changes (:reindex to force)
    \(ANSI.teal)creature local\(ANSI.reset) <prompt>  Ask a model running in-process (MLX, Apple Silicon)
      \(ANSI.teal)creature index\(ANSI.reset) <file>   Index a .swift or .py file into the Rosetta trunk and print its tree
      \(ANSI.teal)creature atlas\(ANSI.reset) <file>   Index a .swift or .py file and print its rolled-up Atlas status tree (syntactic)
      \(ANSI.teal)creature atlas\(ANSI.reset) <dir>    Index a workspace and REAL-type-check it (swiftc); green means it compiles, unprobed shows as ? unknown
      \(ANSI.teal)creature check\(ANSI.reset) <dir>    Same as 'atlas <dir>' — explicit workspace compile-readiness probe
      \(ANSI.teal)creature bridge\(ANSI.reset) <file>  Index a .swift or .py file and print its Bridge dependency graph
      \(ANSI.teal)creature classify\(ANSI.reset) <file> Index a .swift or .py file and tag each node's domain via Foundation (gap-fill-and-learn)
      \(ANSI.teal)creature context\(ANSI.reset) <dir> <query>  Index a workspace and print the nodes retrieval selects for <query> (diagnostic, no LLM)
      \(ANSI.teal)creature ground\(ANSI.reset) <prompt>  Print the verified snippets that would ground this prompt for any model (diagnostic, no LLM)
      \(ANSI.teal)creature cite\(ANSI.reset) <script>  Resolve a key script through the library and print the source (diagnostic, no LLM)
      \(ANSI.teal)creature ask --context\(ANSI.reset) <dir> <prompt>  Ask the creature, grounded in retrieved context from the workspace at <dir>

    \(ANSI.gray)The vessel before the soul.\(ANSI.reset)

    """)
}


// MARK: - Local (embedded/in-process) inference

/// Default embedded soul: 8GB-safe, Apache-2.0, shared Qwen2.5 tokenizer.
/// See RELEASE_PLAN.md "Model management" for the curated soul catalog.
let defaultLocalModelId = "mlx-community/Qwen2.5-3B-Instruct-4bit"

let defaultLocalSystemPrompt = """
You are the creature — a living terminal running entirely on-device. \
Be concise and direct. When asked for code, return only the code unless \
an explanation is explicitly requested.
"""

/// Stop with an instruction if this binary cannot run a model.
///
/// Only matters for in-process (MLX) slots — a purely remote setup needs no
/// Metal. Called before anything constructs an `EmbeddedPartner`, because the
/// underlying failure is a C++ abort that cannot be caught after the fact.
func requireLocalInferenceRuntime() {
    guard !InferenceRuntime.isMetalLibraryAvailable else { return }
    print()
    for line in InferenceRuntime.missingRuntimeGuidance.split(separator: "\n", omittingEmptySubsequences: false) {
        print("  \(ANSI.pink)\(line)\(ANSI.reset)")
    }
    print()
    exit(1)
}

/// True when either slot is configured to run in-process (MLX).
func configUsesLocalSlot(_ config: CreatureConfig) -> Bool {
    SlotProvider.parse(config.consciousURL).isLocal || SlotProvider.parse(config.unconsciousURL).isLocal
}

func cmdLocal(_ prompt: String) async {
    printBanner()

    // "Local" means *on this machine*, which is in-process MLX on Apple Silicon
    // and a local model server (Ollama) everywhere else. `makePartner` owns that
    // choice, so this command works on every platform rather than hard-wiring
    // the Apple-only engine.
    #if canImport(CreatureMLX)
    let engineLabel = "Running in-process (MLX)"
    let modelId = defaultLocalModelId
    let footerLabel = "local · mlx"
    // In-process only: needs MLX's Metal shaders, which only an Xcode build emits.
    requireLocalInferenceRuntime()
    #else
    let engineLabel = "Running against a local model server"
    let modelId = ProcessInfo.processInfo.environment["CREATURE_LOCAL_MODEL"] ?? "qwen2.5-coder"
    let footerLabel = "local · server"
    #endif

    print("  \(ANSI.amber)\(engineLabel)\(ANSI.reset)")
    print("  \(ANSI.gray)\(modelId)\(ANSI.reset)")
    print()

    let partner = makePartner(
        url: SlotProvider.local(modelId: modelId).configValue,
        key: "",
        model: modelId,
        role: .unconscious,
        onProgress: { fraction in
            let pct = Int(fraction * 100)
            FileHandle.standardError.write("  \r\(ANSI.gray)Downloading model… \(pct)%\(ANSI.reset)".data(using: .utf8)!)
        }
    )

    do {
        let start = Date()
        let response = try await partner.complete(prompt: prompt, system: groundedSystem(defaultLocalSystemPrompt, prompt: prompt))
        let elapsedMs = Date().timeIntervalSince(start) * 1000
        print()
        print("  \(ANSI.gray)[\(ANSI.purple)\(footerLabel)\(ANSI.gray) · \(String(format: "%.0f", elapsedMs))ms]\(ANSI.reset)")
        print()
        print(response)
    } catch {
        print()
        print("  \(ANSI.pink)Error: \(error)\(ANSI.reset)")
    }
}

// MARK: - Foundation (Apple on-device, FoundationModels) inference

/// Ask Apple's on-device model (Apple Intelligence via FoundationModels).
/// Availability-gated: if the framework, OS version, or Apple Intelligence
/// itself isn't ready on this machine, prints the specific reason instead
/// of attempting a generation.
func cmdFoundation(_ prompt: String) async {
    printBanner()
    print("  \(ANSI.amber)Running on-device (Apple Intelligence)\(ANSI.reset)")
    print()

    guard let partner = makeFoundationPartner(role: .conscious) else {
        let reason = CreatureInference.foundationUnavailableReason()?.description ?? "unavailable for an unknown reason"
        print("  \(ANSI.pink)Apple Intelligence not enabled — enable it in Settings, or needs macOS 26 + eligible hardware\(ANSI.reset)")
        print("  \(ANSI.gray)(\(reason))\(ANSI.reset)")
        return
    }

    do {
        let start = Date()
        let response = try await partner.complete(prompt: prompt, system: groundedSystem(nil, prompt: prompt))
        let elapsedMs = Date().timeIntervalSince(start) * 1000
        print("  \(ANSI.gray)[\(ANSI.purple)foundation\(ANSI.gray) · \(String(format: "%.0f", elapsedMs))ms]\(ANSI.reset)")
        print()
        print(response)
    } catch {
        print("  \(ANSI.pink)Error: \(error)\(ANSI.reset)")
    }
}


func cmdConfig() async {
    printBanner()
    print("  \(ANSI.amber)Configure the creature's soul(s)\(ANSI.reset)")
    print("  \(ANSI.gray)Local: the creature runs its own model in-process (MLX, no server).\(ANSI.reset)")
    print("  \(ANSI.gray)Remote: any OpenAI-compatible API (Ollama, LM Studio, hosted).\(ANSI.reset)")
    print()

    func prompt(_ label: String, default defaultVal: String = "") -> String {
        if defaultVal.isEmpty {
            print("  \(label): ", terminator: "")
        } else {
            print("  \(label) [\(defaultVal)]: ", terminator: "")
        }
        guard let input = readLine()?.trimmingCharacters(in: .whitespaces), !input.isEmpty else {
            return defaultVal
        }
        return input
    }

    /// Prompts for a slot's provider (local default) and returns the
    /// (url, key, model) triple to store in `CreatureConfig`.
    func promptSlot(
        label: String,
        existingURL: String?,
        existingKey: String?,
        existingModel: String?,
        defaultLocalModel: String,
        role: PartnerRole
    ) -> (url: String, key: String, model: String) {
        let existingProvider = existingURL.map(SlotProvider.parse)
        let defaultChoice: String
        switch existingProvider {
        case .some(.remote): defaultChoice = "remote"
        default: defaultChoice = "local"
        }

        print("  \(ANSI.white)\(label)\(ANSI.reset)")
        let providerChoice = prompt("  Provider (local/remote)", default: defaultChoice).lowercased()

        if providerChoice == "remote" {
            let url = prompt("  \(label) API URL", default: {
                if case .remote(let u)? = existingProvider { return u }
                return "http://localhost:11434"
            }())
            let key = prompt("  \(label) API key", default: existingKey ?? "none")
            let model = prompt("  \(label) model", default: existingModel ?? (role == .conscious ? "llama3.1" : "qwen2.5-coder"))
            return (url, key, model)
        } else {
            let existingModelId: String? = {
                if case .local(let modelId)? = existingProvider { return modelId }
                return nil
            }()
            let modelId = prompt("  \(label) MLX model id", default: existingModelId ?? defaultLocalModel)
            return (SlotProvider.local(modelId: modelId).configValue, "none", modelId)
        }
    }

    let existing = CreatureConfig.load()

    let conscious = promptSlot(
        label: "Conscious",
        existingURL: existing?.consciousURL,
        existingKey: existing?.consciousKey,
        existingModel: existing?.consciousModel,
        defaultLocalModel: defaultConsciousLocalModel,
        role: .conscious
    )
    let unconscious = promptSlot(
        label: "Unconscious",
        existingURL: existing?.unconsciousURL,
        existingKey: existing?.unconsciousKey,
        existingModel: existing?.unconsciousModel,
        defaultLocalModel: defaultUnconsciousLocalModel,
        role: .unconscious
    )

    let config = CreatureConfig(
        consciousURL: conscious.url,
        consciousKey: conscious.key,
        consciousModel: conscious.model,
        unconsciousURL: unconscious.url,
        unconsciousKey: unconscious.key,
        unconsciousModel: unconscious.model,
        profilePath: existing?.profilePath ?? CreatureConfig.defaultProfilePath
    )

    do {
        try config.save()
        print()
        print("  \(ANSI.teal)Saved to ~/.creature/config.json\(ANSI.reset)")
        print("  \(ANSI.gray)Run 'creature calibrate' to sync the pair, or 'creature chat' to start talking.\(ANSI.reset)")
        print()
    } catch {
        print("  \(ANSI.pink)Error saving config: \(error)\(ANSI.reset)")
    }
}

func cmdCalibrate() async {
    printBanner()

    guard let config = CreatureConfig.load() else {
        print("  \(ANSI.pink)No config found. Run 'creature config' first.\(ANSI.reset)")
        return
    }

    // In-process slots need MLX Metal shaders; remote-only setups do not.
    if configUsesLocalSlot(config) { requireLocalInferenceRuntime() }

    let conscious = makePartner(
        url: config.consciousURL,
        key: config.consciousKey,
        model: config.consciousModel,
        role: .conscious
    )

    let unconscious = makePartner(
        url: config.unconsciousURL,
        key: config.unconsciousKey,
        model: config.unconsciousModel,
        role: .unconscious
    )

    print("  \(ANSI.amber)Calibrating...\(ANSI.reset)")
    print("  \(ANSI.gray)Conscious:   \(config.consciousModel)\(ANSI.reset)")
    print("  \(ANSI.gray)Unconscious: \(config.unconsciousModel)\(ANSI.reset)")
    print()

    let handshake = SyncHandshake(
        partnerA: conscious,
        partnerB: unconscious,
        tests: StandardSyncTests.all,
        timeoutSeconds: 120
    )

    let result = await handshake.calibrate()

    switch result {
    case .success(let profile):
        print("  \(ANSI.teal)✓ IN SYNC\(ANSI.reset)")
        print()
        printProfile(profile)
        saveProfile(profile, path: config.profilePath)

    case .partial(let profile, let errors):
        print("  \(ANSI.amber)⚠ Partial sync (\(errors.count) issues)\(ANSI.reset)")
        print()
        printProfile(profile)
        saveProfile(profile, path: config.profilePath)

    case .failure(let error):
        print("  \(ANSI.pink)✗ Calibration failed: \(error)\(ANSI.reset)")
    }
}

func cmdStatus() {
    printBanner()

    guard let config = CreatureConfig.load() else {
        print("  \(ANSI.gray)No config. Run 'creature config' first.\(ANSI.reset)")
        return
    }

    guard let profile = try? SyncProfile.load(from: URL(fileURLWithPath: config.profilePath)) else {
        print("  \(ANSI.gray)No sync profile. Run 'creature calibrate' first.\(ANSI.reset)")
        return
    }

    printProfile(profile)
}


/// Index `contextDirectory`, retrieve nodes relevant to `prompt`, and return
/// (system prompt prefix, node paths used) — the shared "ground `ask` in the
/// trunk" step for both of `cmdAsk`'s partner-invocation paths (the
/// no-sync-profile fallback and the orchestrator path). Returns `("", [])`
/// when `contextDirectory` is `nil`, so callers can unconditionally prepend
/// the result without a separate branch.
///
/// This is the payoff step: the conscious slot's system prompt is no longer
/// just conversation history (`foldHistory`) — it's grounded in retrieved
/// source from the actual codebase at `contextDirectory`.
func resolveAskContext(directory: String?, prompt: String) -> (prefix: String, paths: [String]) {
    guard let directory else { return ("", []) }

    var workspace: WorkspaceIndexer.Workspace
    var warnings: [String] = []
    if let snapshot = WorkspaceIndexer.loadSnapshot(for: directory, warnings: &warnings),
       !WorkspaceIndexer.isSnapshotStale(snapshot, for: directory) {
        workspace = WorkspaceIndexer.workspace(from: snapshot)
        print("  \(ANSI.gray)Loaded context from cache\(ANSI.reset)")
    } else {
        print("  \(ANSI.gray)Indexing context\(ANSI.reset) \(ANSI.gray)\(directory)\(ANSI.reset)")
        let fresh = WorkspaceIndexer.index(directory: directory)
        workspace = fresh
        printWorkspaceCapWarnings(fresh)
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

    let results = ContextRetriever.retrieve(
        query: prompt,
        trunk: workspace.trunk,
        bridge: workspace.bridge,
        limit: ContextDefaults.contextLimit
    )

    let (block, paths) = buildContextBlock(results: results)
    guard !block.isEmpty else {
        print("  \(ANSI.gray)No nodes matched this prompt's terms — asking without grounded context.\(ANSI.reset)")
        print()
        return ("", [])
    }

    print("  \(ANSI.gray)\(paths.count) node(s) retrieved as context\(ANSI.reset)")
    print()
    return (block + "\n\n", paths)
}

/// Who answered. A coordinated result was read out of BOTH phases in the same moment,
/// so naming a single role would be a lie — say so explicitly.
func answeredByLabel(role: PartnerRole, isCoordinated: Bool) -> String {
    guard !isCoordinated else {
        return "\(ANSI.teal)coordinated\(ANSI.reset)\(ANSI.gray) · \(ANSI.blue)conscious\(ANSI.gray)+\(ANSI.purple)unconscious\(ANSI.reset)"
    }
    return role == .conscious
        ? "\(ANSI.blue)conscious\(ANSI.reset)"
        : "\(ANSI.purple)unconscious\(ANSI.reset)"
}

func answeredByLabel(_ result: TaskResult) -> String {
    answeredByLabel(role: result.fromRole, isCoordinated: result.isCoordinated)
}

/// Print the "grounded in" footer listing which node paths were used as
/// context — only when `--context` was actually used (empty `paths` means
/// plain `ask`, which prints nothing extra, preserving its exact prior
/// behaviour).
func printContextFooter(paths: [String]) {
    guard !paths.isEmpty else { return }
    print()
    print("  \(ANSI.gray)[context: \(paths.joined(separator: ", "))]\(ANSI.reset)")
}

func cmdAsk(_ prompt: String, contextDirectory: String? = nil) async {
    let (contextPrefix, contextPaths) = resolveAskContext(directory: contextDirectory, prompt: prompt)

    guard let config = CreatureConfig.load() else {
        print("  \(ANSI.pink)No config. Run 'creature config' first.\(ANSI.reset)")
        return
    }

    // In-process slots need MLX Metal shaders; remote-only setups do not.
    if configUsesLocalSlot(config) { requireLocalInferenceRuntime() }

    guard let profile = try? SyncProfile.load(from: URL(fileURLWithPath: config.profilePath)) else {
        print("  \(ANSI.amber)No sync profile. Run 'creature calibrate' first.\(ANSI.reset)")
        print("  \(ANSI.gray)Defaulting to conscious partner...\(ANSI.reset)")

        // Fallback: just hit conscious directly
        let partner = makePartner(
            url: config.consciousURL,
            key: config.consciousKey,
            model: config.consciousModel,
            role: .conscious
        )
        let system = groundedSystem(contextPrefix.isEmpty ? nil : contextPrefix, prompt: prompt)
        do {
            let response = try await partner.complete(prompt: prompt, system: system)
            print()
            print(response)
            printContextFooter(paths: contextPaths)
        } catch {
            print("  \(ANSI.pink)Error: \(error)\(ANSI.reset)")
        }
        return
    }

    let conscious = makePartner(
        url: config.consciousURL,
        key: config.consciousKey,
        model: config.consciousModel,
        role: .conscious
    )
    let unconscious = makePartner(
        url: config.unconsciousURL,
        key: config.unconsciousKey,
        model: config.unconsciousModel,
        role: .unconscious
    )

    let orchestrator = TerminalOrchestrator(partnerA: conscious, partnerB: unconscious, profile: profile)

    let task = TerminalTask(
        prompt: prompt,
        systemPrompt: groundedSystem(contextPrefix.isEmpty ? nil : contextPrefix, prompt: prompt),
        preferredRole: await resolveRoute(for: prompt)
    )

    let result = await orchestrator.execute(task: task)

    if result.isSuccess {
        let roleLabel = answeredByLabel(result)
        print("  \(ANSI.gray)[\(roleLabel)\(ANSI.gray) · \(String(format: "%.0f", result.latencyMs))ms · \(String(format: "%.0f%%", result.confidence * 100)) confidence]\(ANSI.reset)")
        print()
        print(result.response)
        printContextFooter(paths: contextPaths)
    } else {
        print("  \(ANSI.pink)Error: \(result.error?.localizedDescription ?? "unknown")\(ANSI.reset)")
    }
}

// MARK: - Chat (persistent multi-turn REPL)


func cmdChat(contextDirectory: String? = nil) async {
    printBanner()
    print("  \(ANSI.amber)Chat\(ANSI.reset)  \(ANSI.gray)persistent session · multi-turn · Ctrl-D or :quit to exit\(ANSI.reset)")

    guard let config = CreatureConfig.load() else {
        print("  \(ANSI.pink)No config. Run 'creature config' first.\(ANSI.reset)")
        return
    }

    // In-process slots need MLX Metal shaders; remote-only setups do not.
    if configUsesLocalSlot(config) { requireLocalInferenceRuntime() }

    if let contextDirectory {
        print("  \(ANSI.gray)Indexing context\(ANSI.reset) \(ANSI.gray)\(contextDirectory)\(ANSI.reset)")
    }

    // The whole per-turn pipeline (partners, routing, grounding, context) now
    // lives in ChatEngine (CreatureChat), shared with the IDE. This command is
    // just the terminal skin over it: REPL in, formatted lines out. Model-load
    // progress is surfaced through the engine's callback to stderr, exactly as
    // before, so stdout stays clean.
    let engine = ChatEngine(
        config: config,
        contextDirectory: contextDirectory,
        onModelProgress: { role, fraction in
            let label = role == .conscious ? "conscious" : "unconscious"
            let pct = Int(fraction * 100)
            FileHandle.standardError.write("  \r\(ANSI.gray)Loading \(label) model… \(pct)%\(ANSI.reset)".data(using: .utf8)!)
        }
    )

    if contextDirectory != nil {
        if await engine.contextHitFileCap {
            print("  \(ANSI.amber)⚠ file cap (\(WorkspaceIndexer.maxFiles)) reached — workspace scan stopped early, not all files indexed\(ANSI.reset)")
        }
        if await engine.contextHitByteCap {
            print("  \(ANSI.amber)⚠ total size cap (\(WorkspaceIndexer.maxTotalBytes / 1024 / 1024) MB) reached — workspace scan stopped early\(ANSI.reset)")
        }
        let skipped = await engine.contextSkippedLargeFileCount
        if skipped > 0 {
            print("  \(ANSI.amber)⚠ skipped \(skipped) file(s) over \(WorkspaceIndexer.maxFileBytes / 1024) KB\(ANSI.reset)")
        }
        let files = await engine.contextFileCount ?? 0
        let nodes = await engine.contextNodeCount ?? 0
        print("  \(ANSI.gray)indexed \(files) file(s), \(nodes) node(s)\(ANSI.reset)")
        print("  \(ANSI.gray):reindex to force a re-index\(ANSI.reset)")
    }
    print()

    while true {
        print("  \(ANSI.teal)›\(ANSI.reset) ", terminator: "")
        guard let line = readLine() else {
            // EOF (Ctrl-D)
            print()
            print("  \(ANSI.gray)Goodbye.\(ANSI.reset)")
            break
        }

        let input = line.trimmingCharacters(in: .whitespaces)
        if input.isEmpty {
            continue
        }
        if input == ":quit" || input == ":q" {
            print("  \(ANSI.gray)Goodbye.\(ANSI.reset)")
            break
        }
        if input == ":reindex" {
            guard contextDirectory != nil else {
                print("  \(ANSI.gray)No --context directory for this session — nothing to re-index.\(ANSI.reset)")
                continue
            }
            let count = await engine.reindex()
            print("  \(ANSI.gray)(re-indexed: \(count) file(s))\(ANSI.reset)")
            continue
        }

        let reply = await engine.send(input)

        if reply.isSuccess {
            let roleLabel = answeredByLabel(role: reply.role, isCoordinated: reply.isCoordinated)
            print()
            print(reply.text)
            print()
            print("  \(ANSI.gray)[\(roleLabel)\(ANSI.gray) · \(String(format: "%.0f", reply.latencyMs))ms · \(String(format: "%.0f%%", reply.confidence * 100)) confidence]\(ANSI.reset)")
            printContextFooter(paths: reply.contextPaths)
            print()
        } else {
            print()
            print("  \(ANSI.pink)Error: \(reply.errorDescription ?? "unknown")\(ANSI.reset)")
            print()
        }
    }
}

// MARK: - Helpers

func printProfile(_ profile: SyncProfile) {
    let consciousPartner = profile.roleA == .conscious ? profile.partnerA : profile.partnerB
    let unconsciousPartner = profile.roleA == .unconscious ? profile.partnerA : profile.partnerB

    print("  \(ANSI.blue)Conscious:    \(consciousPartner.name)\(ANSI.reset)  \(ANSI.gray)\(String(format: "%.0f%%", profile.confidenceConscious * 100)) confidence\(ANSI.reset)")
    print("  \(ANSI.purple)Unconscious:  \(unconsciousPartner.name)\(ANSI.reset)  \(ANSI.gray)\(String(format: "%.0f%%", profile.confidenceUnconscious * 100)) confidence\(ANSI.reset)")
    print()
    print("  \(ANSI.gray)Latency delta: \(String(format: "%.0f", profile.latencyDeltaMs))ms\(ANSI.reset)")
    print("  \(ANSI.gray)Status: \(profile.isInSync ? "\(ANSI.teal)IN SYNC" : "\(ANSI.amber)NEEDS ATTENTION")\(ANSI.reset)")
    print()
}

func saveProfile(_ profile: SyncProfile, path: String) {
    do {
        try profile.save(to: URL(fileURLWithPath: path))
        print("  \(ANSI.gray)Profile saved to \(path)\(ANSI.reset)")
    } catch {
        print("  \(ANSI.pink)Failed to save profile: \(error)\(ANSI.reset)")
    }
}

// MARK: - Trunk indexing (polyglot cephalopod dispatch)

/// Which language tentacle handles a file, chosen purely by extension — the
/// CLI-level analogue of "each layer = a language cephalopod" (see
/// `docs/plans/2026-07-05-creature-cursor-competitor-architecture.md` §3).
/// Adding a new tentacle (TS, Rust, …) means adding one more case here and
/// nothing else in this file changes.


/// Index a source file with the tentacle matching its extension and print
/// the resulting trunk tree — one line per `TrunkNode`, indented by
/// structural depth, so real source → real structural trunk is visible from
/// the command line, regardless of which language produced it.
func cmdIndex(_ filePath: String) {
    guard let tentacle = Tentacle(filePath: filePath) else {
        print("  \(ANSI.pink)Unsupported file type: \(filePath) (supported: .swift, .py)\(ANSI.reset)")
        return
    }
    guard let source = try? String(contentsOfFile: filePath, encoding: .utf8) else {
        print("  \(ANSI.pink)Could not read file: \(filePath)\(ANSI.reset)")
        return
    }

    let module = URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent
    let nodes = tentacle.index(source: source, module: module)

    printBanner()
    print("  \(ANSI.amber)Indexing\(ANSI.reset) \(ANSI.gray)\(filePath)\(ANSI.reset)")
    print()

    for node in nodes {
        let indent = String(repeating: "  ", count: max(0, node.coordinate.depth - 1))
        print("  \(indent)\(ANSI.teal)\(node.coordinate.kind)\(ANSI.reset) \(node.coordinate.pathKey) \(ANSI.gray)(depth \(node.coordinate.depth))\(ANSI.reset)")
        if let skeleton = node.channel(at: 0)?.content {
            print("  \(indent)  \(ANSI.gray)channel0: \(skeleton)\(ANSI.reset)")
        }
    }

    print()
    print("  \(ANSI.gray)\(nodes.count) node(s)\(ANSI.reset)")
}

// MARK: - Atlas (rolled-up completion/status tree)

/// ANSI colour for a `DecodedColour` (HSV), converted to the closest 256-colour
/// palette entry. Used for mixed-colour readiness display where a node's colour
/// is the additive blend of per-grammar tracks rather than a flat status.
func ansiColour(for decoded: ColourTrackEncoder.DecodedColour) -> String {
    let h = decoded.hue
    let s = decoded.saturation
    let v = decoded.value

    // Low saturation → grayscale ramp (232-255)
    if s < 0.1 {
        let gray = min(23, max(0, Int(round(v * 23))))
        return "\u{1B}[38;5;\(232 + gray)m"
    }

    // HSV → RGB
    let c = v * s
    let hPrime = h / 60.0
    let x = c * (1.0 - abs((hPrime.truncatingRemainder(dividingBy: 2.0)) - 1.0))
    let m = v - c

    var r: Float = 0, g: Float = 0, b: Float = 0
    switch Int(floor(hPrime)) % 6 {
    case 0: (r, g, b) = (c, x, 0)
    case 1: (r, g, b) = (x, c, 0)
    case 2: (r, g, b) = (0, c, x)
    case 3: (r, g, b) = (0, x, c)
    case 4: (r, g, b) = (x, 0, c)
    default: (r, g, b) = (c, 0, x)
    }

    r += m; g += m; b += m
    let ri = min(5, max(0, Int(round(r * 5))))
    let gi = min(5, max(0, Int(round(g * 5))))
    let bi = min(5, max(0, Int(round(b * 5))))
    let code = 16 + 36 * ri + 6 * gi + bi
    return "\u{1B}[38;5;\(code)m"
}
/// green/amber/red Atlas colour (see `TrunkAtlas.colour(for:)`) — this is
/// just the terminal rendering of the same three-way verdict, not a second
/// source of truth for it.
func ansiColour(for status: TrunkStatus) -> String {
    switch status {
    case .green: return ANSI.teal
    case .yellow: return ANSI.amber
    case .red: return ANSI.pink
    case .unknown: return ANSI.gray
    }
}

func symbol(for status: TrunkStatus) -> String {
    switch status {
    case .green: return "●"
    case .yellow: return "▲"
    case .red: return "✗"
    case .unknown: return "?"
    }
}

/// Format a status symbol with scope. Bare green is unrepresentable.
/// Returns the ANSI-coloured status string, never a bare "green".
func statusWithScope(
    _ status: TrunkStatus,
    coverages: [DiagnosticReducer.GrammarCoverage],
    unit: String? = nil
) -> String {
    let sym = symbol(for: status)
    guard status == .green else { return sym }

    // Green MUST carry scope. If no coverages available, fall back to
    // "unknown scope" — never bare green.
    let grammar = coverages.map { $0.language }.sorted().joined(separator: ", ")
    let scopeUnit = unit ?? coverages.first?.unit ?? "unknown"
    let condition = coverages.first?.condition ?? "unknown"
    return "\(sym) (\(grammar) · \(scopeUnit) · \(condition))"
}

/// Index a source file, build a `TrunkAtlas` with the optional `TrunkBridge`,
/// and print the trunk tree with each node's **rolled-up** status colour —
/// including edge propagation (if a function calls a broken function, it turns
/// red too). This is "see it's green before you compile," the ambient
/// predictive compile-readiness demo.
///
/// HONEST SCOPE: v0 status is syntactic validity only (parse errors) — see
/// `TrunkStatus`'s doc comment. A green tree here means "nothing failed to
/// parse," not "this compiles" or "this type-checks." Edge propagation is
/// direct (one hop) — transitive dependency reddening is a future enhancement.
func cmdAtlas(_ filePath: String) {
    guard let tentacle = Tentacle(filePath: filePath) else {
        print("  \(ANSI.pink)Unsupported file type: \(filePath) (supported: .swift, .py)\(ANSI.reset)")
        return
    }
    guard let source = try? String(contentsOfFile: filePath, encoding: .utf8) else {
        print("  \(ANSI.pink)Could not read file: \(filePath)\(ANSI.reset)")
        return
    }

    let module = URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent
    let (nodes, leafStatus, unresolvedEdges) = tentacle.indexWithBridge(source: source, module: module)

    var trunk = CodeTrunk()
    for node in nodes {
        trunk.add(node)
    }
    let bridge = TrunkBridge.resolve(unresolved: unresolvedEdges, against: trunk)
    let atlas = TrunkAtlas(trunk: trunk, leafStatus: leafStatus, bridge: bridge)

    printBanner()
    print("  \(ANSI.amber)Atlas\(ANSI.reset) \(ANSI.gray)\(filePath)\(ANSI.reset)")
    print("  \(ANSI.gray)v0 scope: syntactic validity + direct edge propagation (one hop)\(ANSI.reset)")
    print("  \(ANSI.gray)        not full compile-readiness or transitive dependency analysis\(ANSI.reset)")
    print()

    for node in nodes {
        let rolledUp = atlas.status(rootedAt: node)
        let indent = String(repeating: "  ", count: max(0, node.coordinate.depth - 1))
        let colour = ansiColour(for: rolledUp)
        print("  \(indent)\(colour)\(symbol(for: rolledUp))\(ANSI.reset) \(ANSI.teal)\(node.coordinate.kind)\(ANSI.reset) \(node.coordinate.pathKey) \(ANSI.gray)(depth \(node.coordinate.depth))\(ANSI.reset)")
    }

    print()
    let overall = atlas.overall
    let overallColour = ansiColour(for: overall)
    switch overall {
    case .green:
        // Single-file probe: the grammar is the tentacle's language, unit is the file's module.
        let grammar = tentacle.language
        let fileUnit = module
        let scoped = "\(symbol(for: .green)) (\(grammar) · \(fileUnit) · unconditioned)"
        print("  \(overallColour)\(scoped)\(ANSI.reset)")
    case .yellow:
        print("  \(overallColour)⚠ yellow — check for warnings\(ANSI.reset)")
    case .red:
        let issueCount = leafStatus.values.filter { $0 == .red }.count
        let edgeRedCount = nodes.filter { atlas.ownStatus(for: $0.id) == .green && atlas.status(rootedAt: $0) == .red }.count
        if edgeRedCount > 0 {
            print("  \(overallColour)✗ red — \(issueCount) syntax issue(s), +\(edgeRedCount) node(s) reddened by edge propagation\(ANSI.reset)")
        } else {
            print("  \(overallColour)✗ red — \(issueCount) issue(s)\(ANSI.reset)")
        }
    case .unknown:
        // Single-file syntactic atlas never produces unknown (nothing here is
        // left unprobed), but the switch must be exhaustive over the verdict.
        print("  \(overallColour)? unknown — not checked\(ANSI.reset)")
    }

    // Print bridge edges if any
    if !bridge.edges.isEmpty {
        print()
        print("  \(ANSI.gray)Bridge edges (\(bridge.edges.count)):\(ANSI.reset)")
        for edge in bridge.edges {
            if let sourceNode = trunk.node(id: edge.source), let targetNode = trunk.node(id: edge.target) {
                print("    \(ANSI.gray)\(sourceNode.coordinate.pathKey) → \(targetNode.coordinate.pathKey)\(ANSI.reset)")
            }
        }
    }
}

// MARK: - Atlas over a workspace (REAL compile-readiness, B3.1)

/// Index a whole workspace directory, run the real compile-readiness probes
/// (`swiftc -typecheck`, workspace-scoped), reduce diagnostics onto nodes, and
/// print the rolled-up Atlas — where green MEANS "type-checks," not merely
/// "parses." This is the B3.1 payoff and the false-green killer: a file that
/// parses but calls an undefined function shows RED here, GREEN under the
/// single-file syntactic `atlas <file>` path.
///
/// HONEST DEGRADE: if a probe is unavailable (no `swiftc` on PATH) or degrades
/// (unresolved external imports — see `SwiftCompileProbe`), the files it would
/// have covered are shown as `?` unknown (grey), never a false green and never
/// a false red. The reason is printed so "unknown" is explained.
func cmdCheck(directory: String) {
    printBanner()
    print("  \(ANSI.amber)Atlas (workspace, real type-check)\(ANSI.reset) \(ANSI.gray)\(directory)\(ANSI.reset)")

    var workspace: WorkspaceIndexer.Workspace
    var atlas: TrunkAtlas
    var diagnostics: [Diagnostic] = []
    var coverages: [DiagnosticReducer.GrammarCoverage] = []
    var readiness: [String: NodeReadiness] = [:]
    var unavailable: [(producer: String, reason: String)] = []
    var loadedFromCache = false

    var warnings: [String] = []
    if let snapshot = WorkspaceIndexer.loadSnapshot(for: directory, warnings: &warnings),
       !WorkspaceIndexer.isSnapshotStale(snapshot, for: directory) {
        workspace = WorkspaceIndexer.workspace(from: snapshot)
        atlas = snapshot.makeAtlas()
        coverages = snapshot.nodes.compactMap { $0.span?.file }.reduce(into: [String: Set<String>]()) { dict, file in
            let ext = URL(fileURLWithPath: file).pathExtension.lowercased()
            dict[ext, default: []].insert(file)
        }.map { lang, files in
            DiagnosticReducer.GrammarCoverage(
                language: lang,
                probedFiles: files,
                diagnostics: [],
                scopeClean: true,
                usrMap: nil,
                unit: "workspace",
                condition: "unconditioned"
            )
        }
        readiness = snapshot.leafStatus.mapValues { status in
            let verdict: GrammarVerdict
            switch status {
            case .green: verdict = .holds(caution: false)
            case .yellow: verdict = .holds(caution: true)
            case .red: verdict = .broken
            case .unknown: verdict = .unprobed
            }
            return NodeReadiness(verdicts: ["swift": verdict])
        }
        loadedFromCache = true
        print("  \(ANSI.gray)Loaded workspace index from cache\(ANSI.reset)")
    } else {
        workspace = WorkspaceIndexer.index(directory: directory)
        printWorkspaceCapWarnings(workspace)
        print("  \(ANSI.gray)\(workspace.fileCount) file(s) indexed, \(workspace.trunk.nodes.count) node(s)\(ANSI.reset)")

        let result = WorkspaceProbe.probe(workspace: workspace)
        atlas = result.atlas
        diagnostics = result.diagnostics
        coverages = result.coverages
        readiness = result.readiness
        unavailable = result.unavailable

        // Save snapshot to cache
        let tree = TreeIndex.from(nodes: workspace.trunk.nodes)
        let leafStatus = readiness.mapValues { TrunkStatus.from(readiness: $0) }
        let engine = RollUpEngine(tree: tree, leafStatus: leafStatus, bridge: workspace.bridge)
        let computedRolledUp = engine.compute()
        let snapshot = CompletionTreeSnapshot(
            nodes: workspace.trunk.nodes,
            treeIndex: tree,
            leafStatus: leafStatus,
            rolledUpStatus: computedRolledUp,
            bridge: workspace.bridge
        )
        try? WorkspaceIndexer.saveSnapshot(snapshot, for: directory)
    }

    // Report any probe that degraded to unknown, with its reason.
    for (producer, reason) in unavailable {
        print("  \(ANSI.gray)? \(producer): \(reason)\(ANSI.reset)")
    }
    print()

    // Per-node tree with rolled-up status colour.
    for node in workspace.trunk.nodes {
        let rolledUp = atlas.status(rootedAt: node)
        let indent = String(repeating: "  ", count: max(0, node.coordinate.depth - 1))

        // Mixed-colour display: if this node has per-grammar readiness with
        // multiple participating grammars, show the additive mix rather than
        // the flat TrunkStatus colour.
        let colour: String
        if let nodeReadiness = readiness[node.id],
           nodeReadiness.languages.count > 1,
           let mixed = ReadinessMixer.mix(nodeReadiness) {
            colour = ansiColour(for: mixed)
        } else {
            colour = ansiColour(for: rolledUp)
        }

        // Per-node scope: grammar from node's channels, unit from pathKey.
        let nodeGrammar = node.channels.first { $0.index >= 1 }?.language ?? "unknown"
        let nodeCoverages = coverages.filter { $0.language == nodeGrammar.lowercased() }
        let nodeUnit = node.coordinate.pathKey.components(separatedBy: ".").first ?? node.coordinate.pathKey
        let statusStr = statusWithScope(rolledUp, coverages: nodeCoverages, unit: nodeUnit)

        print("  \(indent)\(colour)\(statusStr)\(ANSI.reset) \(ANSI.teal)\(node.coordinate.kind)\(ANSI.reset) \(node.coordinate.pathKey) \(ANSI.gray)(depth \(node.coordinate.depth))\(ANSI.reset)")
    }

    // Per-diagnostic detail: file:line + message, grouped by producer.
    if !diagnostics.isEmpty {
        print()
        print("  \(ANSI.gray)Diagnostics (\(diagnostics.count)):\(ANSI.reset)")
        for diagnostic in diagnostics {
            let sevColour: String
            switch diagnostic.severity {
            case .error: sevColour = ANSI.pink
            case .warning: sevColour = ANSI.amber
            case .note: sevColour = ANSI.gray
            }
            let fileName = URL(fileURLWithPath: diagnostic.file).lastPathComponent
            let usrTag = diagnostic.usr.map { " \(ANSI.teal)\($0)\(ANSI.reset)" } ?? ""
            print("    \(sevColour)\(diagnostic.severity.rawValue)\(ANSI.reset) \(ANSI.gray)\(fileName):\(diagnostic.startLine)\(ANSI.reset)\(usrTag) \(diagnostic.message)")
        }
    }

    print()
    let overall = atlas.overall
    let overallColour = ansiColour(for: overall)
    switch overall {
    case .green:
        let scoped = statusWithScope(.green, coverages: coverages)
        print("  \(overallColour)\(scoped)\(ANSI.reset)")
    case .yellow:
        let warnCount = diagnostics.filter { $0.severity == .warning }.count
        print("  \(overallColour)⚠ yellow — \(warnCount) warning(s)\(ANSI.reset)")
    case .red:
        let errorCount = diagnostics.filter { $0.severity == .error }.count
        print("  \(overallColour)✗ red — \(errorCount) type-check error(s)\(ANSI.reset)")
    case .unknown:
        print("  \(overallColour)? unknown — not fully checked (see reasons above); green is not being claimed\(ANSI.reset)")
    }
}

// MARK: - Bridge (dependency graph between trunk nodes)

/// Index a source file, resolve its call edges against the trunk, and print
/// the resulting dependency graph. This is the "tree becomes a graph" demo —
/// each edge shows who calls whom, and cross-language links appear when the
/// same truthKey resolves to multiple nodes.
func cmdBridge(_ filePath: String) {
    guard let tentacle = Tentacle(filePath: filePath) else {
        print("  \(ANSI.pink)Unsupported file type: \(filePath) (supported: .swift, .py)\(ANSI.reset)")
        return
    }
    guard let source = try? String(contentsOfFile: filePath, encoding: .utf8) else {
        print("  \(ANSI.pink)Could not read file: \(filePath)\(ANSI.reset)")
        return
    }

    let module = URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent
    let (nodes, _, unresolvedEdges) = tentacle.indexWithBridge(source: source, module: module)

    var trunk = CodeTrunk()
    for node in nodes {
        trunk.add(node)
    }
    let bridge = TrunkBridge.resolve(unresolved: unresolvedEdges, against: trunk)

    printBanner()
    print("  \(ANSI.amber)Bridge\(ANSI.reset) \(ANSI.gray)\(filePath)\(ANSI.reset)")
    print("  \(ANSI.gray)\(nodes.count) node(s), \(unresolvedEdges.count) unresolved edge(s), \(bridge.edges.count) resolved edge(s)\(ANSI.reset)")
    print()

    if bridge.edges.isEmpty {
        print("  \(ANSI.gray)No resolved edges. Calls may be to symbols outside this file,\(ANSI.reset)")
        print("  \(ANSI.gray)or the indexer did not find any calls in the current scope.\(ANSI.reset)")
    } else {
        for edge in bridge.edges {
            if let sourceNode = trunk.node(id: edge.source), let targetNode = trunk.node(id: edge.target) {
                let kindLabel = edge.kind.rawValue
                print("  \(ANSI.teal)\(sourceNode.coordinate.pathKey)\(ANSI.reset) \(ANSI.gray)\(kindLabel)→\(ANSI.reset) \(ANSI.teal)\(targetNode.coordinate.pathKey)\(ANSI.reset)")
            } else {
                print("  \(ANSI.gray)\(edge.source) \(edge.kind.rawValue)→ \(edge.target)\(ANSI.reset)")
            }
        }
    }
    print()

    // Cross-language linking evidence: if any edge resolves to multiple targets
    let multiTarget = bridge.edges.reduce(into: [String: Set<String>]()) { map, edge in
        map[edge.source, default: []].insert(edge.target)
    }.filter { $0.value.count > 1 }
    if !multiTarget.isEmpty {
        print("  \(ANSI.amber)Cross-language links (one call → multiple targets, same truthKey):\(ANSI.reset)")
        for (sourceID, targets) in multiTarget {
            if let sourceNode = trunk.node(id: sourceID) {
                print("    \(sourceNode.coordinate.pathKey) → \(targets.count) targets")
            }
        }
        print()
    }
}

// MARK: - Classify (Foundation-assist: node domain gap-fill-and-learn)

/// Index a source file, then classify each node's domain via
/// `CreatureTrunkFoundation.classify(trunk:)` — the tentacles give structure,
/// Foundation classifies meaning, and the answer is learned/cached by
/// `truthKey` so Foundation is consulted only for genuinely new skeletons
/// (see `docs/plans/2026-07-05-creature-cursor-competitor-architecture.md`
/// §Build log "Next" #1). The raw oracle call is internal-only, exactly like
/// route classification — only the resulting domain tag is ever printed.
///
/// If Foundation is unavailable on this machine, prints the clean reason
/// (mirroring `cmdFoundation`) and skips classification entirely rather than
/// faking a result.
func cmdClassify(_ filePath: String) async {
    guard let tentacle = Tentacle(filePath: filePath) else {
        print("  \(ANSI.pink)Unsupported file type: \(filePath) (supported: .swift, .py)\(ANSI.reset)")
        return
    }
    guard let source = try? String(contentsOfFile: filePath, encoding: .utf8) else {
        print("  \(ANSI.pink)Could not read file: \(filePath)\(ANSI.reset)")
        return
    }

    printBanner()
    print("  \(ANSI.amber)Classifying\(ANSI.reset) \(ANSI.gray)\(filePath)\(ANSI.reset)")
    print()

    if let reason = CreatureTrunkFoundation.foundationUnavailableReason() {
        print("  \(ANSI.pink)Apple Intelligence not enabled — enable it in Settings, or needs macOS 26 + eligible hardware\(ANSI.reset)")
        print("  \(ANSI.gray)(\(reason.description))\(ANSI.reset)")
        return
    }

    let module = URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent
    let nodes = tentacle.index(source: source, module: module)

    var trunk = CodeTrunk()
    for node in nodes {
        trunk.add(node)
    }

    let outcome = await CreatureTrunkFoundation.classify(trunk: trunk)

    for node in nodes {
        let indent = String(repeating: "  ", count: max(0, node.coordinate.depth - 1))
        let tag = outcome.classifications[node.coordinate.truthKey]
        let domainLabel = tag.map { "\(ANSI.purple)[\($0.domain)]\(ANSI.reset)" } ?? "\(ANSI.gray)[unclassified]\(ANSI.reset)"
        print("  \(indent)\(ANSI.teal)\(node.coordinate.kind)\(ANSI.reset) \(node.coordinate.pathKey) \(domainLabel)")
        if let summary = tag?.summary {
            print("  \(indent)  \(ANSI.gray)\(summary)\(ANSI.reset)")
        }
    }

    print()
    print("  \(ANSI.gray)[\(outcome.oracleCalls) filled by oracle · \(outcome.cacheHits) from cache]\(ANSI.reset)")
}

// MARK: - Context (workspace-wide retrieval, the payoff step)

/// Print the caps-hit warnings `WorkspaceIndexer.index(directory:)` reports —
/// shared by `cmdContext` and `cmdAsk`'s `--context` path so both are equally
/// honest about a truncated workspace scan (see the "no silent truncation"
/// constraint on `WorkspaceIndexer`).
func printWorkspaceCapWarnings(_ workspace: WorkspaceIndexer.Workspace) {
    if workspace.hitFileCap {
        print("  \(ANSI.amber)⚠ file cap (\(WorkspaceIndexer.maxFiles)) reached — workspace scan stopped early, not all files indexed\(ANSI.reset)")
    }
    if workspace.hitByteCap {
        print("  \(ANSI.amber)⚠ total size cap (\(WorkspaceIndexer.maxTotalBytes / 1024 / 1024) MB) reached — workspace scan stopped early\(ANSI.reset)")
    }
    if !workspace.skippedLargeFiles.isEmpty {
        print("  \(ANSI.amber)⚠ skipped \(workspace.skippedLargeFiles.count) file(s) over \(WorkspaceIndexer.maxFileBytes / 1024) KB\(ANSI.reset)")
    }
}

/// Index `directory` and print the `ContextRetriever` results for `query` —
/// no LLM call, purely the deterministic proof that retrieval works: path,
/// kind, score, and a short Channel-1 snippet for every selected node.
func cmdContext(directory: String, query: String) {
    printBanner()
    print("  \(ANSI.amber)Context\(ANSI.reset) \(ANSI.gray)\(directory)\(ANSI.reset)  \(ANSI.gray)query: \"\(query)\"\(ANSI.reset)")
    print()

    var workspace: WorkspaceIndexer.Workspace
    var warnings: [String] = []
    if let snapshot = WorkspaceIndexer.loadSnapshot(for: directory, warnings: &warnings),
       !WorkspaceIndexer.isSnapshotStale(snapshot, for: directory) {
        workspace = WorkspaceIndexer.workspace(from: snapshot)
        print("  \(ANSI.gray)Loaded context from cache\(ANSI.reset)")
    } else {
        let fresh = WorkspaceIndexer.index(directory: directory)
        workspace = fresh
        printWorkspaceCapWarnings(fresh)
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
    print("  \(ANSI.gray)\(workspace.fileCount) file(s) indexed, \(workspace.trunk.nodes.count) node(s), \(workspace.bridge.edges.count) bridge edge(s)\(ANSI.reset)")
    print()

    let results = ContextRetriever.retrieve(
        query: query,
        trunk: workspace.trunk,
        bridge: workspace.bridge,
        limit: ContextDefaults.contextLimit
    )

    if results.isEmpty {
        print("  \(ANSI.gray)No nodes matched this query's terms.\(ANSI.reset)")
        return
    }

    for result in results {
        let node = result.node
        let tag = result.matchedDirectly ? "\(ANSI.teal)match\(ANSI.reset)" : "\(ANSI.purple)+callee\(ANSI.reset)"
        print("  \(tag)  \(ANSI.white)\(node.coordinate.pathKey)\(ANSI.reset)  \(ANSI.gray)(\(node.coordinate.kind) · score \(result.score))\(ANSI.reset)")
        if let snippet = node.channel(at: 1)?.content {
            let oneLine = snippet
                .split(separator: "\n")
                .first
                .map(String.init) ?? snippet
            print("    \(ANSI.gray)\(oneLine.prefix(120))\(ANSI.reset)")
        }
    }

    print()
    print("  \(ANSI.gray)\(results.count) node(s) selected (\(results.filter { $0.matchedDirectly }.count) direct match, \(results.filter { !$0.matchedDirectly }.count) via bridge expansion)\(ANSI.reset)")
}

/// Diagnostic (no LLM): print the exact verified-snippet grounding block that `ask`/
/// `chat`/`local`/`foundation` would inject for `prompt`. Mirrors `context` — it makes
/// the grounding visible and testable without invoking a model. Shows which library is
/// loaded (harvested asset vs bundled constructs only) and the detected language.
func cmdGround(_ prompt: String) {
    printBanner()
    print("  \(ANSI.amber)Ground\(ANSI.reset) \(ANSI.gray)query: \"\(prompt)\"\(ANSI.reset)")
    let libLoaded = snippetRetriever.store != nil
    let libNote = libLoaded ? "harvested library + bundled constructs" : "bundled constructs only (no ~/.creature/library.snip)"
    let lang = groundingLanguage(in: prompt)
    print("  \(ANSI.gray)library: \(libNote) · \(snippetRetriever.languages.languageCount) languages · detected: \(lang ?? "none")\(ANSI.reset)")
    print()

    let block = snippetGrounding(for: prompt)
    guard !block.isEmpty else {
        if !promptWantsCode(prompt) {
            print("  \(ANSI.gray)Not a coding prompt — no grounding injected (kept out of the way).\(ANSI.reset)")
        } else if lang == nil {
            print("  \(ANSI.gray)No language named — grounding stays scoped, so nothing injected. Try e.g. \"… in rust\".\(ANSI.reset)")
        } else {
            print("  \(ANSI.gray)No verified snippet matched.\(ANSI.reset)")
        }
        return
    }
    for line in block.split(separator: "\n", omittingEmptySubsequences: false) {
        print("  \(ANSI.gray)│\(ANSI.reset) \(line)")
    }
}

/// Diagnostic (no LLM): resolve a key script exactly as the unconscious's output would be
/// resolved, and print the source it yields. Reads the harvested library from
/// `$CREATURE_LIBRARY` (or ~/.creature/library.snip).
///
///   creature cite '^abc'
///   creature cite '^abc | os | makedirs | path'
func cmdCite(_ script: String) {
    printBanner()
    guard let store = snippetRetriever.store else {
        print("  \(ANSI.pink)No harvested library. Build one: snippets --save ~/.creature/library.snip\(ANSI.reset)")
        return
    }
    print("  \(ANSI.amber)Cite\(ANSI.reset) \(ANSI.gray)\(store.uniqueLines) keys available\(ANSI.reset)")
    print()

    let detector = KeyScriptBasisDetector(store: store, languages: snippetRetriever.languages)
    guard let source = detector.basis(of: script).codePayload else {
        print("  \(ANSI.pink)Not a resolvable key script.\(ANSI.reset)")
        print("  \(ANSI.gray)Every ^key must exist in the library and every bind must match its hole count.\(ANSI.reset)")
        return
    }
    for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
        print("  \(ANSI.gray)│\(ANSI.reset) \(line)")
    }
}


/// Parse `--context <dir>` out of `ask`'s or `chat`'s arguments, returning
/// the remaining words (joined back into the prompt — unused by `chat`,
/// which takes no prompt words) and the context directory if present.
/// `--context` may appear anywhere in the argument list (before or after any
/// prompt words); only its first occurrence is honoured. Plain
/// `creature ask <prompt>` / `creature chat` (no `--context` anywhere)
/// returns `contextDirectory: nil` and the exact original words untouched —
/// this is what keeps both commands' no-context path byte-for-byte identical
/// to before this feature.
func parseContextArgument(_ args: [String]) -> (prompt: String, contextDirectory: String?) {
    guard let flagIndex = args.firstIndex(of: "--context") else {
        return (args.joined(separator: " "), nil)
    }
    let directoryIndex = args.index(after: flagIndex)
    guard directoryIndex < args.endIndex else {
        // "--context" with no following directory — drop the dangling flag,
        // treat everything else as the prompt, no context directory applied.
        var remaining = args
        remaining.remove(at: flagIndex)
        return (remaining.joined(separator: " "), nil)
    }

    let directory = args[directoryIndex]
    var remaining = args
    remaining.remove(at: directoryIndex)
    remaining.remove(at: flagIndex)
    return (remaining.joined(separator: " "), directory)
}

// MARK: - Entry point

let args = CommandLine.arguments.dropFirst()
let command = args.first ?? "help"

switch command {
case "config":
    await cmdConfig()
case "calibrate":
    await cmdCalibrate()
case "status":
    cmdStatus()
case "ask":
    let (prompt, contextDirectory) = parseContextArgument(Array(args.dropFirst()))
    if prompt.isEmpty {
        print("  Usage: creature ask [--context <dir>] <prompt>")
    } else {
        await cmdAsk(prompt, contextDirectory: contextDirectory)
    }
case "context":
    let rest = Array(args.dropFirst())
    if rest.count < 2 {
        print("  Usage: creature context <dir> <query>")
    } else {
        let directory = rest[0]
        let query = rest.dropFirst().joined(separator: " ")
        cmdContext(directory: directory, query: query)
    }
case "ground":
    let prompt = args.dropFirst().joined(separator: " ")
    if prompt.isEmpty {
        print("  Usage: creature ground <prompt>   (diagnostic: show the verified snippets that would ground this)")
    } else {
        cmdGround(prompt)
    }
case "cite":
    let script = args.dropFirst().joined(separator: " ")
    if script.isEmpty {
        print("  Usage: creature cite '^key [| binding | binding]'   (diagnostic: resolve a citation, no LLM)")
    } else {
        cmdCite(script)
    }
case "chat":
    let (_, chatContextDirectory) = parseContextArgument(Array(args.dropFirst()))
    await cmdChat(contextDirectory: chatContextDirectory)
case "local":
    let prompt = args.dropFirst().joined(separator: " ")
    if prompt.isEmpty {
        print("  Usage: creature local <prompt>")
    } else {
        await cmdLocal(prompt)
    }
case "foundation":
    let prompt = args.dropFirst().joined(separator: " ")
    if prompt.isEmpty {
        print("  Usage: creature foundation <prompt>")
    } else {
        await cmdFoundation(prompt)
    }
case "index":
    if let filePath = args.dropFirst().first {
        cmdIndex(filePath)
    } else {
        print("  Usage: creature index <file.swift|file.py>")
    }
case "bridge":
    if let filePath = args.dropFirst().first {
        cmdBridge(filePath)
    } else {
        print("  Usage: creature bridge <file.swift|file.py>")
    }
case "atlas":
    if let path = args.dropFirst().first {
        // A directory → the real workspace type-check probe (B3.1); a file →
        // the single-file syntactic atlas (unchanged). This is D4: probing is
        // surfaced through an explicit workspace command, not per-chat-turn.
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
            cmdCheck(directory: path)
        } else {
            cmdAtlas(path)
        }
    } else {
        print("  Usage: creature atlas <file.swift|file.py>  (single file, syntactic)")
        print("         creature atlas <dir>                 (workspace, real type-check)")
    }
case "check":
    if let path = args.dropFirst().first {
        cmdCheck(directory: path)
    } else {
        print("  Usage: creature check <dir>  (workspace real compile-readiness)")
    }
case "classify":
    if let filePath = args.dropFirst().first {
        await cmdClassify(filePath)
    } else {
        print("  Usage: creature classify <file.swift|file.py>")
    }
case "--version", "-v":
    print("creature 0.1.0")
case "help", "--help", "-h":
    printUsage()
default:
    // Treat everything as an ask
    let prompt = args.joined(separator: " ")
    await cmdAsk(prompt)
}
