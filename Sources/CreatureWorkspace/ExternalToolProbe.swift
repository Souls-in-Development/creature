// ExternalToolProbe — earned green for the universal languages.
//
// Swift earns green via `swiftc -typecheck` and Python via `ast`. Every other
// catalogued language was structurally indexed but could only ever be UNKNOWN,
// because no tool stood behind it. This probe closes that: it runs a language's
// own single-file validator (`ruby -c`, `php -l`, `node --check`, …) and reports
// the result through the same `CompileProbe` contract, so the honesty rules are
// unchanged:
//
//   - tool not installed        → `.unavailable`  → the file stays UNKNOWN
//     (never a false green just because we couldn't check it)
//   - tool ran, file accepted   → probed + clean  → GREEN (earned: exit 0)
//   - tool ran, file rejected   → a diagnostic     → RED
//
// v0 scope: single-file validation (syntax / parse, the rigor each tool's check
// mode gives — same bar Python's `ast` probe already sets). Cross-file type
// checking for these languages (a real `tsc`/`go build`/`cargo check` over a
// resolved project) is a later, per-language deepening — exactly as it is for
// Swift, whose probe is the one that does a real module type-check today.

import Foundation
import CreatureTrunk

public struct ExternalToolProbe: CompileProbe, @unchecked Sendable {
    public let producer: String
    public let language: String
    let fileExtensions: Set<String>
    let executable: String
    let checkArguments: [String]
    /// Test seam: force the unavailable path by pointing at a missing binary.
    let executableOverride: String?

    public init(
        producer: String,
        language: String,
        fileExtensions: Set<String>,
        executable: String,
        checkArguments: [String],
        executableOverride: String? = nil
    ) {
        self.producer = producer
        self.language = language
        self.fileExtensions = fileExtensions
        self.executable = executable
        self.checkArguments = checkArguments
        self.executableOverride = executableOverride
    }

    public func probe(files: [String]) -> CompileProbeResult {
        let mine = files.filter { fileExtensions.contains(Self.ext(of: $0)) }
        // No files for this language → available-but-empty, not an error.
        guard !mine.isEmpty else {
            return CompileProbeResult(diagnostics: [], probedFiles: [])
        }

        // Tool absent → unknown, never green/red. This is the honest degrade:
        // on a machine without a Rust toolchain, .rs files simply stay UNCHECKED.
        guard let exe = resolvedExecutable() else {
            return .unavailable("\(executable) not found on PATH")
        }

        var diagnostics: [Diagnostic] = []
        var probed: Set<String> = []

        for file in mine {
            guard let run = try? Self.runProcess(executable: exe, arguments: checkArguments + [file]) else {
                // Could not launch the tool for this file → do NOT certify it.
                // Leaving it out of `probedFiles` keeps it UNKNOWN.
                continue
            }
            probed.insert(file)

            if run.exitCode != 0 {
                // A rejection MUST produce a diagnostic, always — otherwise a
                // non-zero exit with unparseable output would slip through as a
                // clean file (the classic false-green). Parse a line if the tool
                // gave one; fall back to the whole file at line 1.
                let (line, message) = Self.firstError(inStderr: run.stderr, orStdout: run.stdout)
                diagnostics.append(Diagnostic(
                    file: file,
                    startLine: line,
                    endLine: line,
                    severity: .error,
                    message: message,
                    producer: producer
                ))
            }
        }

        // scopeClean is true because this is per-file validation: every probed
        // file that carries no error diagnostic was individually accepted (exit
        // 0). The verdict logic returns `.broken` for any file with an attributed
        // error BEFORE consulting scopeClean, so broken files go red and the
        // clean ones earn green — while unprobed files (tool absent / launch
        // failure) are excluded from `probedFiles` and stay unknown.
        return CompileProbeResult(
            diagnostics: diagnostics,
            probedFiles: probed,
            scopeClean: true
        )
    }

    // MARK: - Registry

    /// The single-file validators wired in by default. Each is a tool with a
    /// reliable syntax/parse-check mode that signals validity by exit code.
    /// Membership here is not a promise the tool is installed — an absent tool
    /// degrades that language to UNKNOWN, honestly.
    public static let registry: [ExternalToolProbe] = [
        ExternalToolProbe(producer: "ruby -c", language: "ruby", fileExtensions: ["rb"], executable: "ruby", checkArguments: ["-c"]),
        ExternalToolProbe(producer: "perl -c", language: "perl", fileExtensions: ["pl", "pm"], executable: "perl", checkArguments: ["-c"]),
        ExternalToolProbe(producer: "php -l", language: "php", fileExtensions: ["php", "phtml"], executable: "php", checkArguments: ["-l"]),
        ExternalToolProbe(producer: "bash -n", language: "bash", fileExtensions: ["sh", "bash"], executable: "bash", checkArguments: ["-n"]),
        ExternalToolProbe(producer: "node --check", language: "javascript", fileExtensions: ["js", "mjs", "cjs"], executable: "node", checkArguments: ["--check"]),
        ExternalToolProbe(producer: "luac -p", language: "lua", fileExtensions: ["lua"], executable: "luac", checkArguments: ["-p"]),
        ExternalToolProbe(producer: "gofmt -e", language: "go", fileExtensions: ["go"], executable: "gofmt", checkArguments: ["-e"]),
        ExternalToolProbe(producer: "tsc --noEmit", language: "typescript", fileExtensions: ["ts", "tsx"], executable: "tsc", checkArguments: ["--noEmit", "--skipLibCheck"]),
    ]

    // MARK: - Executable location

    private func resolvedExecutable() -> String? {
        if let executableOverride {
            // Validate the override too — a missing binary must degrade to
            // unavailable (→ unknown), not be trusted as present.
            return FileManager.default.isExecutableFile(atPath: executableOverride) ? executableOverride : nil
        }
        guard let run = try? Self.runProcess(executable: "/usr/bin/env", arguments: ["which", executable]),
              run.exitCode == 0 else { return nil }
        let path = run.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return path
    }

    // MARK: - Parsing

    private static func ext(of path: String) -> String {
        URL(fileURLWithPath: path).pathExtension.lowercased()
    }

    /// Best-effort first-error extraction. Most validators print
    /// `... line N ...` or `path:N:` — pull the first such line number if
    /// present; otherwise blame the whole file at line 1 and carry the raw first
    /// line as the message, so nothing is silently swallowed.
    private static func firstError(inStderr stderr: String, orStdout stdout: String) -> (line: Int, message: String) {
        let text = stderr.isEmpty ? stdout : stderr
        let firstLine = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first.map(String.init) ?? "syntax error"

        // `:<num>:` (path:line:col) or `line <num>`.
        if let n = firstMatch(#":(\d+):"#, in: firstLine) ?? firstMatch(#"line (\d+)"#, in: firstLine) {
            return (max(1, n), firstLine)
        }
        return (1, firstLine)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[r])
    }

    // MARK: - Subprocess

    struct ProcessRun {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    static func runProcess(executable: String, arguments: [String]) throws -> ProcessRun {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        // Drain both pipes before waiting, so a chatty tool can't deadlock on a
        // full buffer.
        let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return ProcessRun(
            exitCode: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
