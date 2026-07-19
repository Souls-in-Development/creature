import Foundation
import CreatureTrunk

/// The Python cephalopod's first tentacle: an indexer that walks Python's own
/// `ast` (via a `python3` subprocess — see `PythonASTScript`) and emits one
/// `TrunkNode` per declaration, in the same Channel-0 vocabulary
/// `SwiftIndexer` uses. A Swift `func add(a: Int, b: Int)` and a Python
/// `def add(a, b)` both normalize to the Channel-0 skeleton `"func add/2"`
/// and therefore share a `truthKey` — that shared key is the whole point of
/// the trunk (see `CodeTrunk.nodesSharing(truthKey:)`).
///
/// **Arity choice for methods:** a Python method's leading `self`/`cls` is
/// dropped from arity when computing its skeleton (see
/// `PythonASTScript`'s doc comment) — `def hello(self)` skeletons as
/// `"func hello/0"`, matching what a caller actually supplies
/// (`greeter.hello()`), and matching the shape a free Swift `func hello()`
/// would report. This is a deliberate normalization choice, not an
/// oversight: without it, every Python method would carry +1 arity purely
/// from its own language's calling convention, and would never link to an
/// equivalent free function or a Swift method (whose `self` is implicit and
/// never counted).
///
/// **Primary path:** shell out to `python3`, feed it `PythonASTScript.source`
/// on stdin, parse the JSON contract described there.
///
/// **Fallback path:** if `python3` cannot be found, cannot be launched, or
/// its output isn't the expected JSON, fall back to `CodeIngester`'s regex
/// extractor (the same one that already backs `CodeIngester.ingest` for
/// Python) so the tentacle still produces *something* rather than nothing —
/// noted with `.yellow` status on every node it produces, since a regex
/// fallback cannot promise the same fidelity as a real AST walk. A genuine
/// Python *syntax error* (the `python3` + `ast` path ran fine and correctly
/// rejected the source) is a different case entirely and is surfaced as
/// `.red` — see `indexWithStatus`.
public enum PythonIndexer {

    /// Index one Python source file into a flat list of `TrunkNode`s — one
    /// per recognized declaration (class/def/top-level or class-level
    /// assignment), nested or top-level, mirroring
    /// `SwiftIndexer.index(source:module:)`.
    public static func index(source: String, module: String) -> [TrunkNode] {
        indexWithStatus(source: source, module: module).nodes
    }

    /// Index one Python source file the same way `index(source:module:)`
    /// does, but also compute each node's own Atlas status — the input
    /// `TrunkAtlas` needs (see `TrunkAtlas.leafStatus`).
    ///
    /// Status rule:
    /// - `python3` ran and `ast.parse` succeeded: every produced node is
    ///   `.green` (v0 scope is syntactic validity only, same honesty as
    ///   `SwiftIndexer` — see `TrunkStatus`'s doc comment).
    /// - `python3` ran and `ast.parse` raised a `SyntaxError`: no nodes are
    ///   produced from the AST path; instead a single synthetic node
    ///   representing the whole file is emitted with `.red` status, so the
    ///   syntax error is visible to the Atlas rather than silently vanishing.
    /// - `python3` is unavailable, failed to launch, or returned output that
    ///   isn't the expected JSON contract: fall back to the regex extractor
    ///   (`CodeIngester`'s Python path); every node produced this way is
    ///   `.yellow` (fallback fidelity, not a known error).
    public static func indexWithStatus(
        source: String,
        module: String
    ) -> (nodes: [TrunkNode], status: [String: TrunkStatus]) {
        switch runAST(source: source) {
        case .success(let declarations, _):
            return buildNodes(from: declarations, module: module)

        case .syntaxError(let message):
            let path = [module]
            let skeletonLine = "file \(module)"
            let truthKey = CodeIngester.truthHash(of: skeletonLine)
            let coordinate = TrunkCoordinate(path: path, kind: "file", truthKey: truthKey)
            let channel0 = TrunkChannel(index: 0, language: "rosetta", content: skeletonLine)
            let channel1 = TrunkChannel(index: 1, language: "python", content: source)
            let id = "\(path.joined(separator: "/"))#python"
            let node = TrunkNode(id: id, coordinate: coordinate, channels: [channel0, channel1])
            _ = message // captured for callers who want it via runAST directly; not surfaced in v0's TrunkNode shape
            return ([node], [id: .red])

        case .unavailable:
            return fallbackIndex(source: source, module: module)
        }
    }

    /// Index one Python source file, returning nodes, status, and a list of
    /// unresolved call edges extracted from the AST. Each edge carries the
    /// source node id of the declaration that contains the call, and the
    /// `truthKey` of the target skeleton so it can be resolved against a
    /// `CodeTrunk` later (see `TrunkBridge.resolve(unresolved:against:)`).
    public static func indexWithBridge(
        source: String,
        module: String
    ) -> (nodes: [TrunkNode], status: [String: TrunkStatus], edges: [UnresolvedEdge]) {
        switch runAST(source: source) {
        case .success(let declarations, let calls):
            let (nodes, status) = buildNodes(from: declarations, module: module)
            var edges: [UnresolvedEdge] = []
            for call in calls {
                let sourcePath = [module] + call.decl_path
                let sourceID = "\(sourcePath.joined(separator: "/"))#python"
                let skeleton = "func \(call.name)/\(call.arity)"
                let targetTruthKey = CodeIngester.truthHash(of: skeleton)
                edges.append(UnresolvedEdge(source: sourceID, targetTruthKey: targetTruthKey, kind: .call))
            }
            return (nodes, status, edges)

        case .syntaxError(let message):
            let path = [module]
            let skeletonLine = "file \(module)"
            let truthKey = CodeIngester.truthHash(of: skeletonLine)
            let coordinate = TrunkCoordinate(path: path, kind: "file", truthKey: truthKey)
            let channel0 = TrunkChannel(index: 0, language: "rosetta", content: skeletonLine)
            let channel1 = TrunkChannel(index: 1, language: "python", content: source)
            let id = "\(path.joined(separator: "/"))#python"
            let node = TrunkNode(id: id, coordinate: coordinate, channels: [channel0, channel1])
            _ = message
            return ([node], [id: .red], [])

        case .unavailable:
            let (nodes, status) = fallbackIndex(source: source, module: module)
            return (nodes, status, [])
        }
    }

    /// Outcome of attempting the `python3` + `ast` path.
    enum ASTResult {
        case success(declarations: [Declaration], calls: [Call])
        case syntaxError(message: String)
        case unavailable
    }

    /// One declaration as decoded from `PythonASTScript`'s JSON contract.
    struct Declaration: Decodable {
        let kind: String
        let name: String
        let arity: Int
        let path: [String]
    }

    /// One call as decoded from `PythonASTScript`'s JSON contract.
    struct Call: Decodable {
        let decl_path: [String]
        let name: String
        let arity: Int
    }

    private struct SuccessPayload: Decodable {
        let ok: Bool
        let declarations: [Declaration]
        let calls: [Call]?
    }

    private struct ErrorPayload: Decodable {
        let ok: Bool
        let error: String
        let message: String
        let lineno: Int?
        let offset: Int?
    }

    /// Locate a `python3` executable. Checks the common absolute locations
    /// first (fast, no shell needed), then falls back to asking `/usr/bin/env`
    /// to resolve it from `PATH` — covers pyenv/asdf/Homebrew shims that
    /// don't live at a fixed path.
    static func locatePython3() -> String? {
        let candidates = ["/usr/bin/python3", "/usr/local/bin/python3", "/opt/homebrew/bin/python3"]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }

        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        which.arguments = ["python3", "-c", "import sys; print(sys.executable)"]
        let out = Pipe()
        which.standardOutput = out
        which.standardError = Pipe()
        do {
            try which.run()
            which.waitUntilExit()
            guard which.terminationStatus == 0 else { return nil }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let resolved = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (resolved?.isEmpty == false) ? resolved : nil
        } catch {
            return nil
        }
    }

    /// Run `PythonASTScript.source` under `python3`, feeding `source` on
    /// stdin, and decode its JSON contract.
    static func runAST(source: String) -> ASTResult {
        guard let pythonPath = locatePython3() else { return .unavailable }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["-c", PythonASTScript.source]

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return .unavailable
        }

        stdin.fileHandleForWriting.write(Data(source.utf8))
        try? stdin.fileHandleForWriting.close()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard !outData.isEmpty else { return .unavailable }

        let decoder = JSONDecoder()
        if let success = try? decoder.decode(SuccessPayload.self, from: outData), success.ok {
            return .success(declarations: success.declarations, calls: success.calls ?? [])
        }
        if let failure = try? decoder.decode(ErrorPayload.self, from: outData), failure.ok == false {
            return .syntaxError(message: failure.message)
        }
        return .unavailable
    }

    /// Turn decoded `Declaration`s into `TrunkNode`s, exactly mirroring
    /// `SwiftIndexer`'s `recordLeaf`: `path = [module] + decl.path`,
    /// Channel-0 skeleton in the shared vocabulary, `truthKey` via
    /// `CodeIngester.truthHash`, Channel 1 labelled `"python"`.
    private static func buildNodes(
        from declarations: [Declaration],
        module: String
    ) -> (nodes: [TrunkNode], status: [String: TrunkStatus]) {
        var nodes: [TrunkNode] = []
        var status: [String: TrunkStatus] = [:]

        for declaration in declarations {
            let path = [module] + declaration.path
            let skeletonLine = skeleton(for: declaration)
            let truthKey = CodeIngester.truthHash(of: skeletonLine)

            let coordinate = TrunkCoordinate(path: path, kind: declaration.kind, truthKey: truthKey)
            let channel0 = TrunkChannel(index: 0, language: "rosetta", content: skeletonLine)
            let channel1 = TrunkChannel(index: 1, language: "python", content: sourceLine(for: declaration))
            let id = "\(path.joined(separator: "/"))#python"

            nodes.append(TrunkNode(id: id, coordinate: coordinate, channels: [channel0, channel1]))
            status[id] = .green
        }

        return (nodes, status)
    }

    /// Channel-0 skeleton line for one declaration, in the SAME vocabulary
    /// `SwiftIndexer` uses: `"func <name>/<arity>"`, `"class <name>"`,
    /// `"var <name>"`.
    private static func skeleton(for declaration: Declaration) -> String {
        switch declaration.kind {
        case "func":
            return "func \(declaration.name)/\(declaration.arity)"
        case "class":
            return "class \(declaration.name)"
        case "var":
            return "var \(declaration.name)"
        default:
            return "\(declaration.kind) \(declaration.name)/\(declaration.arity)"
        }
    }

    /// Channel-1 rendering: v0 does not re-slice the original source text per
    /// declaration (the AST script reports shape, not byte ranges), so
    /// Channel 1 carries the same skeleton-derived signature text a reader
    /// would recognize the declaration by. This is honestly narrower than
    /// `SwiftIndexer`'s Channel 1 (which carries the declaration's real
    /// source text) — a future pass can extend `PythonASTScript` to also
    /// report `col_offset`/`end_col_offset` and slice real source text.
    private static func sourceLine(for declaration: Declaration) -> String {
        switch declaration.kind {
        case "func":
            return "def \(declaration.name)(...)"
        case "class":
            return "class \(declaration.name):"
        case "var":
            return "\(declaration.name) = ..."
        default:
            return "\(declaration.kind) \(declaration.name)"
        }
    }

    // MARK: - Fallback (python3 unavailable)

    /// Regex-based fallback, reusing `CodeIngester`'s existing Python
    /// extractor path (`DeclarationExtractor.extractPython` via
    /// `CodeIngester.normalize`) so the tentacle still works without
    /// `python3` present. Produces a SINGLE file-level node (v0's
    /// `CodeIngester.ingest` shape) rather than SwiftIndexer's per-declaration
    /// nesting, since the regex extractor has no notion of scope/nesting —
    /// every node from this path is `.yellow` (fallback, not a known defect).
    private static func fallbackIndex(
        source: String,
        module: String
    ) -> (nodes: [TrunkNode], status: [String: TrunkStatus]) {
        let node = CodeIngester.ingest(source: source, language: "python", path: [module])
        return ([node], [node.id: .yellow])
    }
}
