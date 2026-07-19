import Foundation

/// The result of running one `CompileProbe` over a workspace: the diagnostics
/// it produced, exactly which files it actually covered, and — if it couldn't
/// run at all — an honest reason.
///
/// The `probedFiles` set is load-bearing: it is what `DiagnosticReducer` uses
/// to tell "checked and clean → green" from "never looked → unknown." A probe
/// that degrades (toolchain absent, unresolved external imports, …) returns an
/// EMPTY `probedFiles` and a non-nil `unavailableReason`, so every node it
/// would have covered correctly reduces to `.unknown` rather than a false
/// green (or a false red).
public struct CompileProbeResult: Sendable {
    /// Findings from this probe (may be empty for a clean, available probe).
    public let diagnostics: [Diagnostic]

    /// The set of files this probe actually type-checked. Empty when the probe
    /// was unavailable or degraded — see `unavailableReason`.
    public let probedFiles: Set<String>

    /// The compiler's OWN affirmative verdict for the whole probed scope: true
    /// iff the toolchain type-checked the probed unit successfully (exit 0).
    ///
    /// THE BOUND. This is the only thing that can *earn* `green`. A node is
    /// never green because "no diagnostic happened to land on it" — that is
    /// green-by-absence, and any gap in the attribution pipeline silently
    /// becomes a false green. Instead: a node can never be greener than its
    /// enclosing scope's verdict. If the scope did not type-check, nothing
    /// inside it can be certified, and attribution only *refines where* the
    /// breakage is — it can never grant health.
    ///
    /// Same rule every build system uses: a Bazel target is green because its
    /// action exited 0, never because no error was attributed to it. Defaults
    /// to `false` deliberately — "not certified" is the honest default; only an
    /// affirmative clean compile flips it.
    public let scopeClean: Bool

    /// Non-nil iff the probe could NOT produce trustworthy diagnostics
    /// (toolchain missing, unresolved external module imports, subprocess
    /// failure). When set, `probedFiles` is empty by contract and every
    /// candidate node degrades to `.unknown`.
    public let unavailableReason: String?

    public init(
        diagnostics: [Diagnostic],
        probedFiles: Set<String>,
        scopeClean: Bool = false,
        unavailableReason: String? = nil
    ) {
        self.diagnostics = diagnostics
        self.probedFiles = probedFiles
        self.scopeClean = scopeClean
        self.unavailableReason = unavailableReason
    }

    /// A probe that could not run — the honest-degrade constructor. No files
    /// probed, no diagnostics, nothing certified, just the reason.
    public static func unavailable(_ reason: String) -> CompileProbeResult {
        CompileProbeResult(diagnostics: [], probedFiles: [], scopeClean: false, unavailableReason: reason)
    }

    /// True when this probe ran and covered at least one file.
    public var isAvailable: Bool { unavailableReason == nil }
}

/// A language-agnostic compile-readiness probe seam. Each tentacle provides one
/// (`SwiftCompileProbe` today; a Python `pyflakes`/`mypy` probe is B3.2). A
/// probe is WORKSPACE-scoped by design: real type-checking crosses files
/// (symbol resolution spans a module), so a probe takes the whole set of files
/// at once, not a single file.
///
/// A missing/absent probe for a language means that language contributes
/// `.unknown`, never a false green — enforced by the `CompileProbeResult`
/// contract above.
public protocol CompileProbe: Sendable {
    /// A short producer name stamped onto every `Diagnostic` this probe emits
    /// (e.g. `"swiftc"`).
    var producer: String { get }

    /// The grammar/language this probe covers, lowercased, matching the language
    /// on the trunk nodes' channels (e.g. `"swift"`). `DiagnosticReducer` keys
    /// coverage by this — it is the probe's grammar identity, distinct from the
    /// tool name in `producer` ("swiftc").
    var language: String { get }

    /// Type-check the given source files as one unit and return diagnostics +
    /// the files actually covered. `files` are absolute (or otherwise
    /// consistently-formed) paths that must match the `SourceSpan.file` values
    /// the tentacle recorded on the corresponding nodes, so the
    /// `DiagnosticReducer` can attribute results back.
    func probe(files: [String]) -> CompileProbeResult
}
