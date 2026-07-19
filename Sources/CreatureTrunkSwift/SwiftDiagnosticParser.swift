import Foundation
import CreatureTrunk

/// Parses `swiftc` (clang-style) stderr into universal `Diagnostic`s, and
/// decides whether a run should be degraded to `unknown` because of unresolved
/// external imports (D2).
///
/// The line format `swiftc` emits, one per diagnostic:
///
///     /abs/path/File.swift:LINE:COL: error|warning|note: MESSAGE
///
/// Lines that don't match (source-context echoes, carets, notes without a
/// location, blank lines) are ignored. Split out from `SwiftCompileProbe` so
/// the parsing is unit-testable on canned stderr with no subprocess.
enum SwiftDiagnosticParser {

    /// Parse every `PATH:LINE:COL: severity: message` line out of `stderr`.
    static func parse(stderr: String, producer: String) -> [Diagnostic] {
        return parse(stderr: stderr, producer: producer, spatialIndex: nil)
    }

    /// Parse every `PATH:LINE:COL: severity: message` line out of `stderr`,
    /// optionally looking up USR for each diagnostic via a spatial index.
    static func parse(stderr: String, producer: String, spatialIndex: SwiftSymbolGraphParser.SpatialIndex?) -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []
        for rawLine in stderr.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            guard let diagnostic = parseLine(line, producer: producer, spatialIndex: spatialIndex) else { continue }
            diagnostics.append(diagnostic)
        }
        return diagnostics
    }

    /// Parse a single stderr line, or `nil` if it isn't a located diagnostic.
    ///
    /// Robust to the fact that a file path can itself contain colons: we scan
    /// for the FIRST `:<int>:<int>: ` run followed by a known severity word,
    /// treating everything before it as the path. This avoids a naive
    /// `split(":")` mis-parsing paths or Windows-style drive letters.
    static func parseLine(_ line: String, producer: String, spatialIndex: SwiftSymbolGraphParser.SpatialIndex? = nil) -> Diagnostic? {
        // Find "<line>:<col>: <severity>: " — locate the severity keyword and
        // walk back to the two integers preceding it.
        let severities: [(String, DiagnosticSeverity)] = [
            ("error:", .error),
            ("warning:", .warning),
            ("note:", .note)
        ]

        for (keyword, severity) in severities {
            guard let keywordRange = line.range(of: ": \(keyword) ")
                    ?? line.range(of: ": \(keyword)")  // message may be empty
            else { continue }

            // Everything before the keyword is "PATH:LINE:COL".
            let prefix = String(line[line.startIndex..<keywordRange.lowerBound])
            let messageStart = keywordRange.upperBound
            let message = String(line[messageStart...]).trimmingCharacters(in: .whitespaces)

            // Split "PATH:LINE:COL" from the RIGHT: last two colon-separated
            // fields are COL and LINE; the rest (which may contain colons) is
            // the path.
            let parts = prefix.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count >= 3,
                  let col = Int(parts[parts.count - 1]),
                  let lineNumber = Int(parts[parts.count - 2])
            else { continue }

            let file = parts[0..<(parts.count - 2)].joined(separator: ":")
            guard !file.isEmpty else { continue }

            let usr = spatialIndex?.usrFor(filePath: file, line: lineNumber)
            return Diagnostic(
                file: file,
                startLine: lineNumber,
                endLine: lineNumber,
                column: col,
                severity: severity,
                message: message,
                producer: producer,
                usr: usr
            )
        }
        return nil
    }

    /// D2: does this diagnostic set indicate an unresolved EXTERNAL import —
    /// i.e. the workspace can't type-check standalone because a module it
    /// imports isn't on the search path? One such failure cascades into many
    /// false "cannot find X in scope" errors, so the whole run is untrustworthy
    /// and must degrade to `unknown` rather than report false reds.
    ///
    /// The unambiguous signal is `swiftc`'s "no such module 'X'" — that is
    /// specifically an import that didn't resolve, not a genuine user error in
    /// the code under test. (We deliberately do NOT treat "cannot find … in
    /// scope" alone as the trigger: that message is exactly the REAL
    /// false-green-killer error we want to report as red when it stems from the
    /// user's own undefined symbol. Only when it cascades FROM a missing module
    /// — detected via "no such module" — do we suppress.)
    static func hasUnresolvedExternalImport(_ diagnostics: [Diagnostic]) -> Bool {
        diagnostics.contains { diagnostic in
            guard diagnostic.severity == .error else { return false }
            let m = diagnostic.message.lowercased()
            return m.contains("no such module")
                || m.contains("could not build")
                || m.contains("missing required module")
        }
    }
}
