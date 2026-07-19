import Foundation
import CreatureTrunk

/// The Swift tentacle's real compile-readiness probe (B3.1): the thing that
/// makes green *mean* "type-checks," not merely "parses." It invokes the real
/// toolchain in type-check-only mode — `swiftc -typecheck` (no codegen, fast) —
/// over the whole workspace as one module, parses the compiler's stderr
/// diagnostics, and hands them to `DiagnosticReducer` as `Diagnostic`s.
///
/// This is the layer that flips the false-green: a file that PARSES cleanly but
/// calls an undefined function is `.green` under the syntactic-only
/// `SwiftIndexer.indexWithStatus`, and `.red` here.
///
/// HONEST DEGRADE (D2) — the probe returns `unknown` (empty `probedFiles` +
/// `unavailableReason`), never a false green and never a false red, when:
///   1. `swiftc` is not found on PATH (via `xcrun --find swiftc`, then plain
///      `swiftc`) — the toolchain is simply absent.
///   2. the type-check fails because of UNRESOLVED EXTERNAL IMPORTS: a real
///      workspace usually imports modules (`Foundation`, third-party packages)
///      that a bare `swiftc -typecheck` of loose files cannot resolve, and one
///      unresolved import cascades into a storm of false "cannot find X in
///      scope" errors downstream. v0 treats that whole run as `unknown` rather
///      than reporting those cascading errors as reds. This is the v0 limit:
///      only a self-contained, import-clean workspace type-checks for real
///      today; wiring a resolvable build graph (SwiftPM/xcodebuild) so real
///      dependencies resolve is a later phase.
public final class SwiftCompileProbe: CompileProbe, @unchecked Sendable {

    public let producer = "swiftc"

    /// The grammar this probe covers — matches the "swift" language on the
    /// trunk nodes' channels (distinct from `producer` = the tool, "swiftc").
    public let language = "swift"

    public var spatialIndex: SwiftSymbolGraphParser.SpatialIndex? = nil

    /// Override for the compiler executable — used by tests to force the
    /// unavailable path by pointing at a non-existent binary. Production leaves
    /// this `nil` and lets `locateSwiftc()` find the real one.
    private let swiftcOverride: String?

    public init(swiftcOverride: String? = nil) {
        self.swiftcOverride = swiftcOverride
    }

    public func probe(files: [String]) -> CompileProbeResult {
        // No Swift files → nothing to probe. Available-but-empty (not an error).
        let swiftFiles = files.filter { $0.hasSuffix(".swift") }
        guard !swiftFiles.isEmpty else {
            return CompileProbeResult(diagnostics: [], probedFiles: [])
        }

        // 1. Locate swiftc. Absent → unavailable (unknown), not green/red.
        guard let swiftc = resolvedSwiftc() else {
            return .unavailable("swiftc not found on PATH (tried xcrun --find swiftc, then swiftc)")
        }
        guard FileManager.default.isExecutableFile(atPath: swiftc) else {
            return .unavailable("swiftc path is not executable: \(swiftc)")
        }

        // Create the symbol graph directory BEFORE the run.
        let symbolGraphDir = NSTemporaryDirectory() + "creature-sg-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: symbolGraphDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: symbolGraphDir) }

        // 2. Run `swiftc -typecheck <files>` as one module; capture stderr + exit
        //    status. `-diagnostic-style llvm` pins the STABLE one-line
        //    `path:line:col: severity: message` contract; swiftc's default
        //    "swift" style prints a pretty multi-line block whose first line only
        //    *happens* to be parseable. Don't rely on luck.
        let run: ProcessRun
        do {
            var arguments = ["-typecheck", "-diagnostic-style", "llvm"]
            // -sdk is REQUIRED on macOS — see `locateSDK()`. Without it swiftc
            // cannot load the standard library and fails on every file.
            if let sdk = Self.locateSDK() { arguments += ["-sdk", sdk] }
            // -emit-module is REQUIRED for -emit-symbol-graph to actually emit
            // .symbols.json files during single-file type-check. The module file
            // itself is not used; we just need the side-effect of symbol graph
            // emission. See Phase 1 plan §Task 4 empirical verification.
            let modulePath = NSTemporaryDirectory() + "creature-mod-\(UUID().uuidString).swiftmodule"
            arguments += [
                "-emit-module",
                "-emit-module-path", modulePath,
                "-emit-symbol-graph",
                "-emit-symbol-graph-dir", symbolGraphDir,
                "-symbol-graph-minimum-access-level", "internal"
            ]
            arguments += swiftFiles
            run = try runProcess(executable: swiftc, arguments: arguments)
            try? FileManager.default.removeItem(atPath: modulePath)
        } catch {
            return .unavailable("failed to launch swiftc: \(error)")
        }

        // After the run: parse the emitted symbol graph from the SAME directory.
        let symbolFiles = (try? FileManager.default.contentsOfDirectory(atPath: symbolGraphDir))?
            .filter { $0.hasSuffix(".symbols.json") }
            .map { symbolGraphDir + "/" + $0 } ?? []
        let allSymbols = symbolFiles.flatMap { SwiftSymbolGraphParser.parseSymbolGraph(at: $0) }
        self.spatialIndex = SwiftSymbolGraphParser.SpatialIndex(symbols: allSymbols)
        let diagnostics = SwiftDiagnosticParser.parse(stderr: run.stderr, producer: producer, spatialIndex: self.spatialIndex)

        // 3. D2 external-import degrade: if any diagnostic signals an
        //    unresolved external import, the whole run is untrustworthy (that
        //    one import cascades into many false errors). Degrade to unknown.
        if SwiftDiagnosticParser.hasUnresolvedExternalImport(diagnostics) {
            return .unavailable(
                "workspace does not type-check standalone (unresolved external imports) — degraded to unknown"
            )
        }

        // 4. Never let UNPARSEABLE evidence vanish. If the compiler failed but we
        //    extracted no located error from its output, we know something is
        //    wrong and we know nothing about *what* — so we cannot certify or
        //    condemn any node, and we must say WHY, loudly.
        //
        //    This is the sibling of "never drop an unattributable diagnostic."
        //    It is exactly how the B3 false-green survived: swiftc failed with
        //    `<unknown>:0: error: unable to load standard library` (no
        //    file:line:col → zero parsed diagnostics), and "covered + no
        //    diagnostics" was read as green.
        let parsedAnError = diagnostics.contains { $0.severity == .error }
        if run.exitCode != 0 && !parsedAnError {
            let firstLine = run.stderr
                .split(separator: "\n", omittingEmptySubsequences: true)
                .first.map(String.init) ?? "<no stderr>"
            return .unavailable(
                "swiftc failed (exit \(run.exitCode)) but emitted no located diagnostics — cannot check: \(firstLine)"
            )
        }

        // 5. The scope verdict — the compiler's own affirmative answer. Exit 0
        //    means it type-checked the whole probed unit; anything else means it
        //    did NOT, and nothing inside may be certified green (see
        //    `CompileProbeResult.scopeClean`). This exit status was previously
        //    captured and discarded — that single omission was the false-green.
        return CompileProbeResult(
            diagnostics: diagnostics,
            probedFiles: Set(swiftFiles),
            scopeClean: run.exitCode == 0
        )
    }

    // MARK: - swiftc location

    /// The compiler executable to use: the test override if set, else the
    /// located real `swiftc`.
    private func resolvedSwiftc() -> String? {
        if let swiftcOverride { return swiftcOverride }
        return Self.locateSwiftc()
    }

    /// Find `swiftc`: `xcrun --find swiftc` first (the canonical Xcode-toolchain
    /// path on macOS), then a plain `swiftc` resolved via `/usr/bin/env`.
    /// Returns an absolute path, or `nil` if neither resolves. Public so callers
    /// (and tests) can branch on toolchain availability without running a full
    /// probe — used to keep swiftc-dependent tests honest where no toolchain
    /// exists.
    public static func locateSwiftc() -> String? {
        if let viaXcrun = try? runProcessStatic(executable: "/usr/bin/xcrun", arguments: ["--find", "swiftc"]),
           viaXcrun.exitCode == 0 {
            let path = viaXcrun.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        if let viaEnv = try? runProcessStatic(executable: "/usr/bin/env", arguments: ["which", "swiftc"]),
           viaEnv.exitCode == 0 {
            let path = viaEnv.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// The platform SDK path (`xcrun --show-sdk-path`), or `nil` where there is
    /// no `xcrun` (Linux) — there the toolchain finds its stdlib unaided.
    ///
    /// REQUIRED on macOS. `xcrun --find swiftc` yields a real compiler path, but
    /// invoking that binary DIRECTLY — as `Process` does — inherits no `SDKROOT`
    /// or `DEVELOPER_DIR`, so swiftc fails on EVERY file with:
    ///
    ///     <unknown>:0: error: unable to load standard library for target ...
    ///
    /// That error carries no `file:line:col`, so it parses to zero diagnostics.
    /// Combined with the old "covered + no diagnostics ⇒ green" rule, it meant
    /// the probe never type-checked anything and reported the whole workspace
    /// green. `xcrun swiftc …` works only because `xcrun` sets that environment
    /// up first; passing `-sdk` explicitly gets the same result without a second
    /// process in the middle.
    public static func locateSDK() -> String? {
        guard let run = try? runProcessStatic(executable: "/usr/bin/xcrun", arguments: ["--show-sdk-path"]),
              run.exitCode == 0 else { return nil }
        let path = run.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return nil }
        return path
    }

    // MARK: - Subprocess

    private struct ProcessRun {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private func runProcess(executable: String, arguments: [String]) throws -> ProcessRun {
        try Self.runProcessStatic(executable: executable, arguments: arguments)
    }

    private static func runProcessStatic(executable: String, arguments: [String]) throws -> ProcessRun {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Read both pipes fully BEFORE waitUntilExit to avoid deadlocking on a
        // full pipe buffer when the compiler emits a lot of diagnostics.
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return ProcessRun(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }
}
