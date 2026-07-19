import Testing
import Foundation
@testable import CreatureTrunkSwift
import CreatureTrunk

/// B3.1 Swift real type-check probe tests. The swiftc-dependent cases branch on
/// `SwiftCompileProbe.locateSwiftc()`: on a machine with a toolchain (this one
/// has Xcode) they assert the real green/red; where swiftc is absent they
/// assert `.unknown` — never letting "no swiftc" masquerade as a passing red.
@Suite struct SwiftCompileProbeTests {

    /// Is a real swiftc available on this test machine?
    private var swiftcAvailable: Bool { SwiftCompileProbe.locateSwiftc() != nil }

    /// Write source files into a fresh temp dir and return their absolute paths.
    private func writeFiles(_ files: [(name: String, source: String)]) throws -> (dir: URL, paths: [String]) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("creature-probe-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var paths: [String] = []
        for file in files {
            let url = dir.appendingPathComponent(file.name)
            try file.source.write(to: url, atomically: true, encoding: .utf8)
            paths.append(url.path)
        }
        return (dir, paths)
    }

    // MARK: - Fixture A: the false-green killer

    /// A file that PARSES but does NOT type-check (calls an undefined function).
    /// The syntactic `indexWithStatus` marks this `.green` (it parses); the real
    /// probe must produce an error diagnostic → `.red`. That contrast is the
    /// entire point of B3.
    @Test func parsesButDoesNotTypeCheckProducesErrorDiagnostic() throws {
        let (dir, paths) = try writeFiles([(
            "Bad.swift",
            """
            func caller() {
                let x: Int = someUndefinedFunction()
                print(x)
            }
            """
        )])
        defer { try? FileManager.default.removeItem(at: dir) }

        // Confirm the syntactic-only path is fooled: this source parses clean.
        let (_, syntacticStatus) = SwiftIndexer.indexWithStatus(
            source: try String(contentsOfFile: paths[0], encoding: .utf8),
            module: "Bad", file: paths[0]
        )
        #expect(syntacticStatus.values.allSatisfy { $0 == .green })  // GREEN under v0 — the lie

        let result = SwiftCompileProbe().probe(files: paths)

        guard swiftcAvailable else {
            // No toolchain → honest unknown, NOT a false red/green.
            #expect(!result.isAvailable)
            #expect(result.probedFiles.isEmpty)
            return
        }

        // With swiftc: an error diagnostic on Bad.swift, and the file was probed.
        #expect(result.isAvailable)
        #expect(result.probedFiles.contains(paths[0]))
        #expect(result.diagnostics.contains { $0.severity == .error && $0.file == paths[0] })
    }

    // MARK: - Fixture B: clean

    @Test func cleanSourceTypeChecksWithNoDiagnostics() throws {
        let (dir, paths) = try writeFiles([(
            "Good.swift",
            """
            func add(a: Int, b: Int) -> Int {
                return a + b
            }
            """
        )])
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = SwiftCompileProbe().probe(files: paths)

        guard swiftcAvailable else {
            #expect(!result.isAvailable)
            return
        }

        #expect(result.isAvailable)
        #expect(result.probedFiles.contains(paths[0]))
        #expect(result.diagnostics.filter { $0.severity == .error }.isEmpty)
    }

    // MARK: - Fixture C: honest degrade (unavailable compiler)

    @Test func nonexistentCompilerDegradesToUnavailable() throws {
        let (dir, paths) = try writeFiles([(
            "Any.swift",
            "func f() -> Int { 1 }"
        )])
        defer { try? FileManager.default.removeItem(at: dir) }

        // Point the probe at a compiler that does not exist.
        let probe = SwiftCompileProbe(swiftcOverride: "/nonexistent/definitely/not/swiftc")
        let result = probe.probe(files: paths)

        #expect(!result.isAvailable)
        #expect(result.unavailableReason != nil)
        #expect(result.probedFiles.isEmpty)      // NOT green
        #expect(result.diagnostics.isEmpty)      // NOT red
    }

    // MARK: - D2: unresolved external import degrade

    @Test func unresolvedExternalImportDegradesToUnknownNotRed() throws {
        let (dir, paths) = try writeFiles([(
            "Import.swift",
            """
            import DefinitelyNotARealModule123
            func f() { print("hi") }
            """
        )])
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = SwiftCompileProbe().probe(files: paths)

        guard swiftcAvailable else {
            #expect(!result.isAvailable)
            return
        }

        // "no such module" cascades — the run is degraded to unavailable
        // (unknown), NOT reported as a false red.
        #expect(!result.isAvailable)
        #expect(result.probedFiles.isEmpty)
    }

    @Test func emptyFileListIsAvailableButProbesNothing() {
        let result = SwiftCompileProbe().probe(files: [])
        #expect(result.isAvailable)
        #expect(result.probedFiles.isEmpty)
        #expect(result.diagnostics.isEmpty)
    }
}

/// The stderr parser, tested on canned compiler output — no subprocess. Uses
/// the exact modern swiftc line shape (with source-context echo lines that must
/// be ignored).
@Suite struct SwiftDiagnosticParserTests {

    @Test func parsesErrorLineWithAbsolutePath() {
        let stderr = "/abs/path/Bad.swift:2:18: error: cannot find 'someUndefinedFunction' in scope"
        let diagnostics = SwiftDiagnosticParser.parse(stderr: stderr, producer: "swiftc")

        #expect(diagnostics.count == 1)
        let d = diagnostics[0]
        #expect(d.file == "/abs/path/Bad.swift")
        #expect(d.startLine == 2)
        #expect(d.column == 18)
        #expect(d.severity == .error)
        #expect(d.message == "cannot find 'someUndefinedFunction' in scope")
        #expect(d.producer == "swiftc")
    }

    @Test func ignoresSourceContextEchoLines() {
        // Modern swiftc prints the offending source line and a caret — neither
        // is a located diagnostic; only the first line is.
        let stderr = """
        /abs/Bad.swift:2:18: error: cannot find 'foo' in scope
        1 | func caller() {
        2 |     let x = foo()
          |             `- error: cannot find 'foo' in scope
        """
        let diagnostics = SwiftDiagnosticParser.parse(stderr: stderr, producer: "swiftc")
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .error)
    }

    @Test func parsesWarningAndNoteSeverities() {
        let stderr = """
        /a/File.swift:10:5: warning: variable 'y' was never used
        /a/File.swift:10:5: note: consider replacing with '_'
        """
        let diagnostics = SwiftDiagnosticParser.parse(stderr: stderr, producer: "swiftc")
        #expect(diagnostics.count == 2)
        #expect(diagnostics.contains { $0.severity == .warning })
        #expect(diagnostics.contains { $0.severity == .note })
    }

    @Test func detectsUnresolvedExternalImport() {
        let diagnostics = [
            Diagnostic(file: "/a/F.swift", startLine: 1, endLine: 1, severity: .error,
                       message: "no such module 'Foo'", producer: "swiftc")
        ]
        #expect(SwiftDiagnosticParser.hasUnresolvedExternalImport(diagnostics))
    }

    @Test func undefinedSymbolAloneIsNotTreatedAsExternalImport() {
        // A genuine user error ("cannot find X in scope") must NOT trip the
        // external-import degrade — that is the real false-green-killer red.
        let diagnostics = [
            Diagnostic(file: "/a/F.swift", startLine: 2, endLine: 2, severity: .error,
                       message: "cannot find 'someUndefinedFunction' in scope", producer: "swiftc")
        ]
        #expect(!SwiftDiagnosticParser.hasUnresolvedExternalImport(diagnostics))
    }
}

/// The Swift indexer now records source spans (B3.1 item 3) — verify without
/// removing any existing indexing behaviour.
@Suite struct SwiftIndexerSpanTests {

    @Test func nodesCarrySourceSpansKeyedByFile() {
        let source = """
        struct Greeter {
            func hello() -> String { "hi" }
        }
        """
        let nodes = SwiftIndexer.index(source: source, module: "Demo", file: "/x/Demo.swift")

        let structNode = nodes.first { $0.coordinate.path == ["Demo", "Greeter"] }
        #expect(structNode?.span?.file == "/x/Demo.swift")
        #expect(structNode?.span?.startLine == 1)

        let helloNode = nodes.first { $0.coordinate.path == ["Demo", "Greeter", "hello"] }
        // hello is on line 2 — its span must be tighter (start >= the struct's).
        #expect(helloNode?.span?.startLine == 2)
    }

    @Test func spanDefaultsToModuleNameWhenNoFileGiven() {
        let nodes = SwiftIndexer.index(source: "func f() {}", module: "Mod")
        #expect(nodes.first?.span?.file == "Mod")
    }
}
