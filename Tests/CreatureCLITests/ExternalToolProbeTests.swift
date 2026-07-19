import Testing
import Foundation
@testable import CreatureCLI
import CreatureWorkspace
import CreatureTrunk

/// Earned green for the universal languages: an external validator runs, and the
/// CompileProbe honesty contract turns its verdict into green / red / unknown.
@Suite struct ExternalToolProbeTests {

    private func write(_ contents: String, ext: String) throws -> String {
        let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("creature-probe-\(UUID().uuidString).\(ext)")
        try contents.write(to: path, atomically: true, encoding: .utf8)
        return path.path
    }

    // MARK: - Tool-independent contract (deterministic, no toolchain needed)

    @Test func absentToolDegradesToUnavailableNeverCertifies() throws {
        // A probe whose executable does not exist must NOT certify anything — it
        // returns .unavailable with empty probedFiles, so every file it would
        // have covered stays UNKNOWN. This is the anti-false-green guarantee.
        let file = try write("anything", ext: "rb")
        let probe = ExternalToolProbe(
            producer: "nope", language: "ruby", fileExtensions: ["rb"],
            executable: "definitely-not-a-real-tool",
            checkArguments: ["-c"],
            executableOverride: "/nonexistent/definitely-not-a-real-tool"
        )
        let result = probe.probe(files: [file])
        #expect(result.isAvailable == false)
        #expect(result.probedFiles.isEmpty)
        #expect(result.scopeClean == false)
    }

    @Test func noMatchingFilesIsAvailableButEmpty() {
        // A ruby probe over a workspace with no .rb files is not an error — it
        // simply covers nothing.
        let probe = ExternalToolProbe.registry.first { $0.language == "ruby" }!
        let result = probe.probe(files: ["/tmp/foo.swift", "/tmp/bar.go"])
        #expect(result.isAvailable)
        #expect(result.probedFiles.isEmpty)
        #expect(result.diagnostics.isEmpty)
    }

    @Test func registryCoversTheExpectedLanguages() {
        let langs = Set(ExternalToolProbe.registry.map { $0.language })
        #expect(langs.contains("ruby"))
        #expect(langs.contains("javascript"))
        #expect(langs.contains("bash"))
    }

    // MARK: - Real validator (guarded: skip cleanly if bash is absent)

    /// bash ships on macOS and virtually every Linux, so it is the safest tool
    /// to assert real green/red against. If it is somehow missing, the probe
    /// degrades to unavailable and we assert only the honest-degrade contract.
    private var bashProbe: ExternalToolProbe {
        ExternalToolProbe.registry.first { $0.language == "bash" }!
    }

    @Test func validFileEarnsCleanScope() throws {
        let file = try write("#!/bin/bash\nfoo() { echo hi; }\n", ext: "sh")
        let result = bashProbe.probe(files: [file])
        guard result.isAvailable else { return }  // bash absent → nothing to assert
        #expect(result.probedFiles.contains(file))
        #expect(result.scopeClean)               // exit 0 → clean
        #expect(result.diagnostics.isEmpty)      // → this file earns green
    }

    @Test func brokenFileProducesErrorDiagnostic() throws {
        // Unterminated `if` → bash -n rejects it.
        let file = try write("#!/bin/bash\nif true; then\n  echo hi\n", ext: "sh")
        let result = bashProbe.probe(files: [file])
        guard result.isAvailable else { return }  // bash absent
        #expect(result.probedFiles.contains(file))
        let errors = result.diagnostics.filter { $0.severity == .error && $0.file == file }
        #expect(!errors.isEmpty)                 // → this file goes red
    }
}
