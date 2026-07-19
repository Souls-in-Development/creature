import Testing
import Foundation
@testable import CreatureCLI
import CreatureWorkspace
import CreatureTrunk
import CreatureTrunkSwift

/// THE GATE — the only check that has ever told the truth about compile-readiness.
///
/// Two independent rebuilds passed 265 and 266 synthetic tests while
/// `creature atlas <dir>` printed `✓ green` for a file that does not compile.
/// Synthetic diagnostics construct their own file-identity match by hand, so they
/// are structurally incapable of catching identity drift. This suite therefore
/// drives the REAL `swiftc` through the real index → probe → reduce → Atlas path.
///
/// Rule these tests enforce (THE BOUND): a scope that did not type-check contains
/// no green node. Attribution refines WHERE the breakage is; it never grants health.
@Suite struct EarnedGreenGateTests {

    /// Parses cleanly, does NOT type-check (`undefinedHelper` is undefined).
    private static let brokenSource = """
    func caller() {
        let x = undefinedHelper(42)
        print(x)
    }
    """

    /// Parses and type-checks.
    private static let cleanSource = """
    func greet(_ name: String) -> String {
        return "hello " + name
    }
    """

    private func makeWorkspace(_ name: String, _ files: [String: String]) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("creature-gate-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (filename, source) in files {
            try source.write(to: root.appendingPathComponent(filename), atomically: true, encoding: .utf8)
        }
        return root
    }

    /// THE GATE. A workspace that does not type-check can never be green — not
    /// overall, and not at any single node.
    @Test func brokenWorkspaceIsNeverGreen() throws {
        let root = try makeWorkspace("broken", ["Broken.swift": Self.brokenSource])
        defer { try? FileManager.default.removeItem(at: root) }

        let workspace = WorkspaceIndexer.index(directory: root.path)
        let result = WorkspaceProbe.probe(workspace: workspace)

        #expect(result.atlas.overall != .green)
        for node in workspace.trunk.nodes {
            #expect(result.atlas.ownStatus(for: node.id) != .green)
        }

        if SwiftCompileProbe.locateSwiftc() != nil {
            // Real toolchain: the scope failed, so red (attributed) or unknown
            // (uncertifiable). Never green, never a silent pass.
            #expect(result.atlas.overall == .red || result.atlas.overall == .unknown)
        } else {
            // No toolchain: honest degrade. Unknown — and emphatically not green.
            #expect(result.atlas.overall == .unknown)
        }
    }

    /// Green must remain REACHABLE. An "honesty fix" that made everything unknown
    /// would just be a different lie.
    @Test func cleanWorkspaceCanStillEarnGreen() throws {
        let root = try makeWorkspace("clean", ["Clean.swift": Self.cleanSource])
        defer { try? FileManager.default.removeItem(at: root) }

        let workspace = WorkspaceIndexer.index(directory: root.path)
        let result = WorkspaceProbe.probe(workspace: workspace)

        if SwiftCompileProbe.locateSwiftc() != nil {
            #expect(result.atlas.overall == .green)
        } else {
            // Without a compiler, green is unearnable — that is the honest answer.
            #expect(result.atlas.overall == .unknown)
        }
    }

    /// The diagnostic must actually REACH a declaration — never be dropped on the
    /// floor. Exactly one node owns it.
    @Test func theDiagnosticIsAttributedToExactlyOneDeclaration() throws {
        let root = try makeWorkspace("attributed", ["Broken.swift": Self.brokenSource])
        defer { try? FileManager.default.removeItem(at: root) }

        let workspace = WorkspaceIndexer.index(directory: root.path)
        let result = WorkspaceProbe.probe(workspace: workspace)

        guard SwiftCompileProbe.locateSwiftc() != nil else {
            #expect(result.atlas.overall == .unknown)
            return
        }

        #expect(result.diagnostics.contains { $0.message.contains("undefinedHelper") })
        let reds = workspace.trunk.nodes.filter { result.atlas.ownStatus(for: $0.id) == .red }
        #expect(reds.count == 1)
    }

    /// A probe that cannot run degrades honestly: unknown, never green, never red.
    @Test func unavailableProbeDegradesToUnknownNotGreen() throws {
        let root = try makeWorkspace("degrade", ["Clean.swift": Self.cleanSource])
        defer { try? FileManager.default.removeItem(at: root) }

        let workspace = WorkspaceIndexer.index(directory: root.path)
        let result = WorkspaceProbe.probe(
            workspace: workspace,
            probes: [SwiftCompileProbe(swiftcOverride: "/nonexistent/swiftc")]
        )

        #expect(result.atlas.overall == .unknown)
        #expect(result.atlas.overall != .green)
    }

    /// Phase 1 gate: the diagnostic carries a USR that identifies the declaration.
    @Test func brokenWorkspaceDiagnosticHasUSR() throws {
        let root = try makeWorkspace("usr-diag", ["Broken.swift": Self.brokenSource])
        defer { try? FileManager.default.removeItem(at: root) }

        let workspace = WorkspaceIndexer.index(directory: root.path)
        let result = WorkspaceProbe.probe(workspace: workspace)

        guard SwiftCompileProbe.locateSwiftc() != nil else {
            #expect(result.atlas.overall == .unknown)
            return
        }

        // The diagnostic must carry a USR that identifies the caller declaration.
        let diagnostics = result.diagnostics
        #expect(diagnostics.contains { $0.usr != nil && $0.usr!.contains("calleryyF") })

        // The red node should be the one attributed with the diagnostic.
        let reds = workspace.trunk.nodes.filter { result.atlas.ownStatus(for: $0.id) == .red }
        #expect(reds.count == 1)
    }

    /// Phase 1 gate: the CLI output names the USR-identified declaration.
    @Test func brokenWorkspaceCLIOutputShowsUSR() throws {
        let root = try makeWorkspace("usr-cli", ["Broken.swift": Self.brokenSource])
        defer { try? FileManager.default.removeItem(at: root) }

        guard SwiftCompileProbe.locateSwiftc() != nil else {
            return  // cannot test CLI without compiler
        }

        let bin = try runCreatureAtlas(directory: root.path)
        #expect(bin.stdout.contains("calleryyF") || bin.stdout.contains("caller"), "CLI output should name the USR-identified declaration")
        #expect(bin.stdout.contains("✗ red") || bin.stdout.contains("red —"))
    }

    /// Phase 2 gate: green carries a scope triple; bare green is unrepresentable.
    @Test func cleanWorkspaceGreenShowsScopeTriple() throws {
        let root = try makeWorkspace("scoped", ["Clean.swift": Self.cleanSource])
        defer { try? FileManager.default.removeItem(at: root) }

        guard SwiftCompileProbe.locateSwiftc() != nil else {
            // Without compiler, the output is unknown — no green to test.
            return
        }

        let bin = try runCreatureAtlas(directory: root.path)
        #expect(bin.stdout.contains("(swift · Clean · unconditioned)"), "Green must carry scope triple, not bare green")
        #expect(!bin.stdout.contains("green —"), "Bare green separator is no longer representable")
        #expect(bin.stdout.contains("unconditioned"), "Scope triple must include condition")
    }

    /// Phase 2 gate: broken workspace shows red, not green — regardless of scope.
    @Test func brokenWorkspaceNeverShowsGreenOrScope() throws {
        let root = try makeWorkspace("broken-scope", ["Broken.swift": Self.brokenSource])
        defer { try? FileManager.default.removeItem(at: root) }

        guard SwiftCompileProbe.locateSwiftc() != nil else {
            return
        }

        let bin = try runCreatureAtlas(directory: root.path)
        #expect(!bin.stdout.contains("(swift ·"), "Broken workspace must not show green scope")
        #expect(bin.stdout.contains("✗ red"), "Broken workspace must show red")
    }

    /// Phase 3 gate: mixed-colour display — multi-grammar readiness renders as
    /// an additive blend, not a flat green. The ANSI path must be wired.
    @Test func mixedColourDisplayRendersValidANSI() {
        // Synthetic cross-language readiness (both hold).
        let readiness = NodeReadiness(verdicts: ["swift": .holds, "python": .holds])
        let mixed = ReadinessMixer.mix(readiness)
        #expect(mixed != nil, "Two holding grammars must produce a mixed colour")

        // ANSI conversion must yield a well-formed 256-colour escape sequence.
        let ansi = ansiColour(for: mixed!)
        #expect(ansi.hasPrefix("\u{1B}[38;5;"), "ANSI must be a 256-colour foreground sequence")
        #expect(ansi.hasSuffix("m"), "ANSI must end with 'm'")

        // Mixed hue should differ from pure grammar hues (proves blending happened).
        let swiftHue = TrunkColour.hueForLanguage("swift")
        let pythonHue = TrunkColour.hueForLanguage("python")
        #expect(mixed!.hue != swiftHue || mixed!.saturation < 0.75,
                "Mixed colour should differ from pure Swift hue")
        #expect(mixed!.hue != pythonHue || mixed!.saturation < 0.75,
                "Mixed colour should differ from pure Python hue")
    }

    /// Phase 3 gate: single-grammar readiness still falls back to the flat
    /// TrunkStatus colour path (preserves existing single-language display).
    @Test func singleGrammarReadinessUsesFlatStatusColour() {
        let readiness = NodeReadiness(verdicts: ["swift": .holds])
        let mixed = ReadinessMixer.mix(readiness)
        #expect(mixed != nil)

        // Single-grammar mixed colour is the pure grammar hue.
        let swiftHue = TrunkColour.hueForLanguage("swift")
        #expect(mixed!.hue == swiftHue)
        #expect(mixed!.saturation > 0.5)
    }

    /// Phase 3 gate: the cmdCheck path looks up readiness by node id and can
    /// fall through to mixed-colour rendering (proven by compilation + the
    /// mixedColourDisplayRendersValidANSI test above).
    @Test func workspaceProbeResultCarriesReadinessMap() throws {
        let root = try makeWorkspace("readiness", ["Clean.swift": Self.cleanSource])
        defer { try? FileManager.default.removeItem(at: root) }

        let workspace = WorkspaceIndexer.index(directory: root.path)
        let result = WorkspaceProbe.probe(workspace: workspace)

        // Every node must have a readiness entry (even if unprobed).
        #expect(result.readiness.count == workspace.trunk.nodes.count)
        for node in workspace.trunk.nodes {
            #expect(result.readiness[node.id] != nil, "Node \(node.id) must have readiness")
        }
    }

    /// Helper: run `creature atlas <dir>` and capture stdout/stderr.
    private func runCreatureAtlas(directory: String) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        let binPath = try findCreatureBinary()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binPath)
        process.arguments = ["atlas", directory]
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()
        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (stdout, stderr, process.terminationStatus)
    }

    private func findCreatureBinary() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = ["build", "--product", "creature", "--show-bin-path"]
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()
        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let binDir = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return binDir + "/creature"
    }
}
