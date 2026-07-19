import Foundation

/// Where a trunk node lives in real source: a file and an inclusive line range.
///
/// This is what lets a compiler diagnostic (`file:line:col: error: …`) be
/// attributed back to the node it belongs to — the reducer
/// (`DiagnosticReducer`) matches a diagnostic's file + line against each node's
/// span, and the innermost node whose `[startLine, endLine]` contains the
/// line owns the diagnostic. Tentacles populate this at index time (SwiftSyntax
/// and Python's `ast` both expose per-declaration source locations).
///
/// Optional on `TrunkNode` (see `TrunkNode.span`) so synthetic/test nodes — and
/// every existing call site — keep working without one; a node with no span is
/// simply never the target of span-based attribution.
public struct SourceSpan: Hashable, Sendable, Codable {
    /// The source file this node came from. Compared to `Diagnostic.file` for
    /// attribution — the reducer's caller decides the path convention (absolute
    /// vs relative) and must keep node spans and diagnostics consistent.
    public let file: String

    /// First source line of this node's declaration (1-based, inclusive).
    public let startLine: Int

    /// Last source line of this node's declaration (1-based, inclusive).
    public let endLine: Int

    public init(file: String, startLine: Int, endLine: Int) {
        self.file = file
        self.startLine = startLine
        self.endLine = endLine
    }

    /// True if `line` falls within this span's inclusive `[startLine, endLine]`
    /// (file equality is checked separately by the reducer).
    public func contains(line: Int) -> Bool {
        line >= startLine && line <= endLine
    }

    /// Number of lines this span covers — used to pick the INNERMOST node when
    /// several nodes' spans contain the same diagnostic line (the smallest span
    /// is the most specific / most deeply nested one).
    public var lineCount: Int {
        max(0, endLine - startLine)
    }
}
