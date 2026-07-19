import Foundation
import CreatureTrunk

/// A Python compile-readiness probe using `pyflakes`.
///
/// `pyflakes` is a linter, not a type-checker. Its "holds" is a weaker,
/// heuristic claim than `swiftc`'s affirmative exit-0. It catches undefined
/// names and unused imports, but NOT type errors or runtime behaviour.
/// This is exactly right for a dynamic language: "looks syntactically clean
/// and no obvious static issues" — not "will run correctly."
public struct PyflakesProbe: CompileProbe {
    public let producer = "pyflakes"
    public let language = "python"

    public func probe(files: [String]) -> CompileProbeResult {
        let pythonFiles = files.filter { $0.hasSuffix(".py") }
        guard !pythonFiles.isEmpty else {
            return .unavailable("no Python files in workspace")
        }

        guard let pyflakes = Self.locatePyflakes() else {
            return .unavailable("pyflakes not found in PATH")
        }

        let run: ProcessRun
        do {
            run = try Self.runProcess(executable: pyflakes, arguments: pythonFiles)
        } catch {
            return .unavailable("failed to launch pyflakes: \(error)")
        }

        let diagnostics = Self.parsePyflakesOutput(stderr: run.stderr, stdout: run.stdout)
        let scopeClean = run.exitCode == 0 && diagnostics.isEmpty

        return CompileProbeResult(
            diagnostics: diagnostics,
            probedFiles: Set(pythonFiles),
            scopeClean: scopeClean,
            unavailableReason: nil
        )
    }

    /// Parse pyflakes output into Diagnostics.
    ///
    /// Pyflakes formats each issue as:
    ///   file:line:col  message
    ///
    /// Examples:
    ///   /tmp/test.py:1:1 undefined name 'x'
    ///   /tmp/test.py:3:1 'os' imported but unused
    static func parsePyflakesOutput(stderr: String, stdout: String) -> [Diagnostic] {
        // Pyflakes writes to stdout, not stderr.
        let lines = stdout.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.compactMap { parseLine(String($0)) }
    }

    static func parseLine(_ line: String) -> Diagnostic? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Format: file:line:col  message
        // The message is separated from the location by two spaces.
        guard let spaceRange = trimmed.range(of: "  ") else { return nil }
        let locationPart = String(trimmed[..<spaceRange.lowerBound])
        let message = String(trimmed[spaceRange.upperBound...]).trimmingCharacters(in: .whitespaces)

        // Parse location: file:line:col
        let components = locationPart.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard components.count == 3,
              let lineNum = Int(components[1]),
              let colNum = Int(components[2]) else { return nil }

        let filePath = String(components[0])

        return Diagnostic(
            file: filePath,
            startLine: lineNum,
            endLine: lineNum,
            column: colNum,
            severity: .error,  // pyflakes issues are static errors
            message: message,
            producer: "pyflakes",
            usr: nil  // pyflakes does not emit USRs
        )
    }

    static func locatePyflakes() -> String? {
        let candidates = ["/usr/bin/pyflakes", "/usr/local/bin/pyflakes", "/opt/homebrew/bin/pyflakes"]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        // Try PATH lookup.
        let run = try? runProcess(executable: "/usr/bin/which", arguments: ["pyflakes"])
        if let path = run?.stdout.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty,
           FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    // MARK: - Subprocess helper (mirrors SwiftCompileProbe's private pattern)

    private struct ProcessRun {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private static func runProcess(executable: String, arguments: [String]) throws -> ProcessRun {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

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
