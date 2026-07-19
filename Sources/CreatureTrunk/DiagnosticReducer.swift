import Foundation

/// Reduces per-language probe results into the `[nodeID: NodeReadiness]` map the
/// Atlas consumes — the B3 substrate that turns "the compiler said `file:line:
/// error: …`" into "the swift grammar is BROKEN over this node, while the python
/// grammar still holds."
///
/// This is the reworked reducer: its output is the B3 **primitive** —
/// interleaved per-grammar verdicts (`NodeReadiness`), one verdict per language
/// that participates in each node — NOT a flat status enum. A discrete
/// `TrunkStatus` is only ever *derived* from this (see `TrunkStatus.from`).
///
/// The universal contract (language-agnostic — Swift, Python, and any future
/// tentacle feed the same reducer):
///
///  1. **Participation.** A node participates in a language iff it carries a
///     channel in that language (channel index ≥ 1; channel 0 is the
///     language-agnostic truth). Each participating language gets its own
///     verdict track for that node.
///  2. **Coverage per grammar.** For each participating language:
///       - if that language's probe COVERED the node's file and no diagnostic
///         touched the node → `.holds` (checked and clean);
///       - if a diagnostic touched the node → `.broken` (a hard error) or
///         `.holds(caution: true)` (a warning — a lesser issue that still
///         compiles);
///       - if that language's probe did NOT cover the node's file (toolchain
///         absent / degraded / no probe for the language) → `.unprobed`
///         (present but weightless — never a false hold).
///  3. **Attribution.** Each diagnostic attaches to the INNERMOST node whose
///     `SourceSpan` is in the same file and whose inclusive line range contains
///     the diagnostic's line (smallest containing span). A diagnostic that lands
///     on no node's span attaches to that file's shallowest node so a
///     module-level error is never silently dropped.
///  4. **Fold worst-of per grammar.** Multiple diagnostics from the SAME
///     language on one node combine worst-of (an error + a warning → broken).
///
/// The reducer never invents nodes and never mutates the trunk; it only reads
/// spans off the nodes the tentacles already produced.
public enum DiagnosticReducer {

    /// One language grammar's probe coverage: the language it speaks, the files
    /// it actually type-checked, and the diagnostics it produced. A degraded /
    /// unavailable probe passes an EMPTY `probedFiles` so every node it would
    /// have covered reduces to `.unprobed` (never a false hold).
    public struct GrammarCoverage: Sendable {
        /// The language this probe speaks (lowercased; matches the language on
        /// the nodes' channels, e.g. "swift").
        public let language: String
        /// The exact set of files this probe type-checked.
        public let probedFiles: Set<String>
        /// The findings this probe emitted.
        public let diagnostics: [Diagnostic]
        /// Optional USR → node ID map for compiler-provided precise attribution.
        public let usrMap: [String: String]?
        /// The compiler's affirmative verdict for the whole probed scope (exit 0).
        /// THE BOUND — the only thing that can earn `holds`. See
        /// `CompileProbeResult.scopeClean`. No default: callers must state it.
        public let scopeClean: Bool
        /// The unit this coverage probed (e.g., module name, workspace path, or
        /// file name). Part of the scope triple ⟨grammar · unit · condition⟩.
        public let unit: String
        /// The condition under which this coverage holds (e.g., "unconditioned").
        /// Part of the scope triple ⟨grammar · unit · condition⟩.
        public let condition: String

        public init(
            language: String,
            probedFiles: Set<String>,
            diagnostics: [Diagnostic],
            scopeClean: Bool,
            usrMap: [String: String]? = nil,
            unit: String = "workspace",
            condition: String = "unconditioned"
        ) {
            self.language = language.lowercased()
            self.probedFiles = probedFiles
            self.diagnostics = diagnostics
            self.scopeClean = scopeClean
            self.usrMap = usrMap
            self.unit = unit
            self.condition = condition
        }
    }

    /// Produce `[nodeID: NodeReadiness]` — per node, a verdict for every
    /// language that participates in it.
    ///
    /// - Parameters:
    ///   - coverages: one `GrammarCoverage` per language probe that ran (or
    ///     degraded). Absent languages simply have no coverage, so nodes in them
    ///     reduce to `.unprobed`.
    ///   - trunk: the indexed workspace whose nodes carry `SourceSpan`s and
    ///     language channels.
    /// - Returns: a `NodeReadiness` for EVERY node in the trunk.
    public static func reduce(
        coverages: [GrammarCoverage],
        trunk: CodeTrunk
    ) -> [String: NodeReadiness] {
        // Index coverages by language for O(1) lookup, and pre-attribute each
        // language's diagnostics to node ids (worst-of per node per language).
        let coverageByLanguage: [String: GrammarCoverage] = Dictionary(
            coverages.map { ($0.language, $0) },
            uniquingKeysWith: { a, b in
                // Merge two coverages for the same language (defensive; normally
                // one probe per language): union files, concatenate diagnostics.
                GrammarCoverage(
                    language: a.language,
                    probedFiles: a.probedFiles.union(b.probedFiles),
                    diagnostics: a.diagnostics + b.diagnostics,
                    // A merged scope is certified only if BOTH were. Any failure
                    // taints the union — never the other way round.
                    scopeClean: a.scopeClean && b.scopeClean,
                    usrMap: (a.usrMap ?? [:]).merging(b.usrMap ?? [:]) { first, _ in first },
                    unit: a.unit == b.unit ? a.unit : "\(a.unit), \(b.unit)",
                    condition: a.condition == b.condition ? a.condition : "\(a.condition), \(b.condition)"
                )
            }
        )

        // For each language, map nodeID → worst diagnostic severity attributed.
        var attributions: [String: [String: DiagnosticSeverity]] = [:]  // language → nodeID → severity
        for coverage in coverageByLanguage.values {
            var perNode: [String: DiagnosticSeverity] = [:]
            for diagnostic in coverage.diagnostics {
                let owner: String?
                if let usr = diagnostic.usr, let nodeID = coverage.usrMap?[usr] {
                    owner = nodeID
                } else {
                    owner = owningNodeID(for: diagnostic, in: trunk)
                }
                guard let owner else { continue }
                let existing = perNode[owner]
                perNode[owner] = worse(existing, diagnostic.severity)
            }
            attributions[coverage.language] = perNode
        }

        var readiness: [String: NodeReadiness] = [:]
        for node in trunk.nodes {
            var verdicts: [String: GrammarVerdict] = [:]
            for language in participatingLanguages(of: node) {
                verdicts[language] = verdict(
                    for: node,
                    language: language,
                    coverage: coverageByLanguage[language],
                    attributed: attributions[language]?[node.id]
                )
            }
            readiness[node.id] = NodeReadiness(verdicts: verdicts)
        }
        return readiness
    }

    /// The languages a node participates in: the languages of its channels at
    /// index ≥ 1 (channel 0 is the language-agnostic truth, not a grammar). A
    /// node with only a Channel-0 (or no channels) participates in nothing.
    static func participatingLanguages(of node: TrunkNode) -> [String] {
        node.channels
            .filter { $0.index >= 1 }
            .map { $0.language.lowercased() }
            .reduce(into: [String]()) { acc, lang in
                if !acc.contains(lang) { acc.append(lang) }
            }
    }

    /// One grammar's verdict over one node, given its probe coverage and any
    /// diagnostic attributed to the node from that grammar.
    private static func verdict(
        for node: TrunkNode,
        language: String,
        coverage: GrammarCoverage?,
        attributed: DiagnosticSeverity?
    ) -> GrammarVerdict {
        // Unprobed unless this grammar's probe actually covered the node's file.
        guard let coverage, let span = node.span, coverage.probedFiles.contains(span.file) else {
            return .unprobed
        }

        // A diagnostic positively attributed to this node REFINES where the
        // breakage is. Attribution can narrow blame; it can never grant health.
        if attributed == .error { return .broken }

        // THE BOUND: a node can never be greener than its enclosing scope's
        // verdict. Only the compiler's affirmative clean verdict for the whole
        // probed unit earns `holds`. If the scope did not type-check, we cannot
        // certify this node — `unprobed` (→ unknown), NEVER green. This is what
        // makes a gap anywhere in the attribution pipeline surface as a loud
        // "not checked" instead of a silent false green.
        guard coverage.scopeClean else { return .unprobed }

        // Scope is clean. Now a lesser finding only downgrades to caution.
        if attributed == .warning { return .holds(caution: true) }
        return .holds  // certified clean (a `.note` is not a problem)
    }

    /// Worst-of two severities (for folding multiple diagnostics of one grammar
    /// on one node). error > warning > note; a nil existing loses to any real one.
    private static func worse(_ existing: DiagnosticSeverity?, _ new: DiagnosticSeverity) -> DiagnosticSeverity {
        guard let existing else { return new }
        return rank(existing) >= rank(new) ? existing : new
    }

    private static func rank(_ s: DiagnosticSeverity) -> Int {
        switch s {
        case .error:   return 2
        case .warning: return 1
        case .note:    return 0
        }
    }

    /// The node a diagnostic belongs to, or `nil` if no indexed node lives in
    /// the diagnostic's file. Attribution order (unchanged from B3.0):
    ///
    ///  - INNERMOST node whose span (same file) contains the diagnostic's start
    ///    line — smallest containing span wins (deepest declaration);
    ///  - else the file's shallowest node (top-level/module) so module-level
    ///    diagnostics still land somewhere.
    private static func owningNodeID(for diagnostic: Diagnostic, in trunk: CodeTrunk) -> String? {
        let line = diagnostic.startLine

        let sameFile = trunk.nodes.filter { $0.span?.file == diagnostic.file }
        guard !sameFile.isEmpty else { return nil }

        let containing = sameFile.filter { $0.span?.contains(line: line) == true }
        if let innermost = containing.min(by: { spanLineCount($0) < spanLineCount($1) }) {
            return innermost.id
        }

        return sameFile.min(by: { lhs, rhs in
            let ld = lhs.coordinate.depth
            let rd = rhs.coordinate.depth
            if ld != rd { return ld < rd }
            let ll = lhs.span?.startLine ?? Int.max
            let rl = rhs.span?.startLine ?? Int.max
            return abs(ll - line) < abs(rl - line)
        })?.id
    }

    /// Line count of a node's span, or `Int.max` when it has none (so a
    /// span-less node never wins the innermost tie-break).
    private static func spanLineCount(_ node: TrunkNode) -> Int {
        node.span?.lineCount ?? Int.max
    }
}
