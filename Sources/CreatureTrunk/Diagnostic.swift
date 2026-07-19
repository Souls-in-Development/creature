import Foundation

/// The severity of one `Diagnostic`, and its pure map into the universal
/// `TrunkStatus` verdict.
///
/// Mirrors the three levels every real compiler emits (`error`, `warning`,
/// `note`) so a probe can pass compiler output through unflattened; the
/// reduction to `TrunkStatus` is where those three collapse onto the Atlas's
/// traffic-light.
public enum DiagnosticSeverity: String, Codable, Sendable, Hashable, CaseIterable {
    /// A hard failure — the code does not type-check / compile. → `.red`.
    case error
    /// A non-fatal concern the compiler flagged. → `.yellow`.
    case warning
    /// Informational; attached to another diagnostic or purely advisory.
    /// Contributes nothing to health (→ `.green`, i.e. a no-op under worst-of).
    case note

    /// Pure severity → `TrunkStatus`. `error → .red`, `warning → .yellow`,
    /// `note → .green` (a note is not a problem: folded under worst-of it
    /// never worsens a node's status). Deliberately total and side-effect-free
    /// so the reducer stays trivially testable.
    public var trunkStatus: TrunkStatus {
        switch self {
        case .error:   return .red
        case .warning: return .yellow
        case .note:    return .green
        }
    }
}

/// One finding a probe emitted about a specific place in the source — the
/// universal, language-agnostic currency B3 introduces. A `CompileProbe`
/// (`swiftc`, later `pyflakes`/`mypy`, …) produces `[Diagnostic]`; the
/// `DiagnosticReducer` attributes each one to a trunk node by source span.
///
/// The line range is inclusive and 1-based, matching how compilers report and
/// how `SourceSpan` stores node ranges. A single-line diagnostic has
/// `startLine == endLine`.
public struct Diagnostic: Codable, Sendable, Hashable {
    /// The source file this diagnostic points at — must use the SAME path
    /// convention as the `SourceSpan.file` on the nodes it will be matched
    /// against (see `DiagnosticReducer`).
    public let file: String

    /// First line the diagnostic covers (1-based, inclusive).
    public let startLine: Int

    /// Last line the diagnostic covers (1-based, inclusive). Equal to
    /// `startLine` for a point diagnostic.
    public let endLine: Int

    /// Column of the diagnostic, when the producer reports one. Advisory only —
    /// attribution is by line range, not column.
    public let column: Int?

    /// How serious this finding is (drives the `TrunkStatus`).
    public let severity: DiagnosticSeverity

    /// The human-readable message exactly as the producer emitted it.
    public let message: String

    /// Which probe emitted this (e.g. `"swiftc"`, `"pyflakes"`) — provenance,
    /// so a mixed-language / multi-tool diagnostic set stays attributable.
    public let producer: String

    /// Optional USR (Unified Symbol Resolution) from the compiler's symbol graph.
    /// Phase 1: compiler-provided identity for precise attribution.
    public let usr: String?

    public init(
        file: String,
        startLine: Int,
        endLine: Int,
        column: Int? = nil,
        severity: DiagnosticSeverity,
        message: String,
        producer: String,
        usr: String? = nil
    ) {
        self.file = file
        self.startLine = startLine
        self.endLine = endLine
        self.column = column
        self.severity = severity
        self.message = message
        self.producer = producer
        self.usr = usr
    }
}
