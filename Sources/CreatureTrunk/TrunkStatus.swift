import Foundation

/// A DERIVED, discrete "is this ready?" summary for one trunk node — a
/// convenience roll-up label, **not** the B3 readiness primitive.
///
/// IMPORTANT (B3 rework): readiness is stored as interleaved per-grammar colour
/// tracks (`NodeReadiness` → `ReadinessMixer`), because languages sharing a
/// concept do not share a grammar and a flat per-node verdict throws away
/// exactly that per-grammar distinction. This enum is now **derived from** the
/// mixed readiness (`from(readiness:)`), kept only because a single discrete
/// label is still useful for CLI text, the structural roll-up's worst-of
/// aggregation, and a future compile gate. It is no longer what the Atlas
/// stores.
///
/// The four derived labels and what each means, in terms of the per-grammar
/// verdicts they summarize:
///
/// - `green` — every participating grammar HOLDS (and none flagged a caution).
///   In the colour model this is the strongest, most universal readiness —
///   white when several grammars hold, a pure hue when one does.
/// - `yellow` — every participating grammar holds, but at least one raised a
///   non-fatal caution (a compiler *warning*). Still compiles; just flagged.
/// - `red` — at least one participating grammar is BROKEN (a hard error attributed
///   to this node). That grammar has dropped out of the "holds" mix.
/// - `unknown` — **not checked.** No participating grammar was probed (toolchain
///   absent, or the probe degraded honestly — see `SwiftCompileProbe`), so
///   there is no hold to claim. Emphatically **not** green: an unprobed node
///   must never masquerade as health. Shown distinctly (grey) and, in Atlas
///   roll-up, it blocks a subtree from claiming a confident green.
///
/// SCOPE NOTE: before B3, a node's status reflected **syntactic validity
/// only** (did the declaration parse). B3 introduces real compile-readiness:
/// a Swift grammar's verdict now comes from `swiftc -typecheck` (see
/// `SwiftCompileProbe`), so `green` can mean "type-checks," not merely
/// "parses."
public enum TrunkStatus: Int, Codable, Sendable, CaseIterable, Comparable {
    /// All clear — actually checked and no known issue at or below this node.
    case green = 0
    /// Caution — a known lesser issue (a compiler warning) somewhere at or
    /// below this node.
    case yellow = 1
    /// Broken — a known hard issue (a compiler error, or a syntax/parse error)
    /// somewhere at or below this node.
    case red = 2
    /// Not checked — no probe covered this node. Never green (never claims
    /// health), never a false red. Appended with a distinct raw value (3) so
    /// the persisted/Codable raw values of the existing three do NOT shift;
    /// its position in the worst-of ordering is carried by `severity`, not by
    /// this raw value.
    case unknown = 3

    /// Semantic worst-of rank, DECOUPLED from `rawValue` (so `unknown`'s raw
    /// value can stay 3 without making it the worst status). Ordering:
    ///
    ///   green (0) < unknown (1) < yellow (2) < red (3)
    ///
    /// This yields exactly the required roll-up semantics under the existing
    /// `max`-based `worst`:
    ///   - `worst(green, unknown) == unknown`  (an unprobed node blocks a
    ///     confident green — a subtree with any `unknown` can't roll up green)
    ///   - `worst(yellow, unknown) == yellow`  (a known warning is worse than
    ///     "didn't check")
    ///   - `worst(red, unknown) == red`
    public var severity: Int {
        switch self {
        case .green:   return 0
        case .unknown: return 1
        case .yellow:  return 2
        case .red:     return 3
        }
    }

    /// `Comparable` is defined on `severity`, NOT `rawValue`, so "worst of a
    /// set" is simply `max(by: <)` / `.max()` and honours the semantic
    /// ordering above rather than the raw storage values.
    public static func < (lhs: TrunkStatus, rhs: TrunkStatus) -> Bool {
        lhs.severity < rhs.severity
    }

    /// The worse of two statuses under the semantic ordering (red beats yellow
    /// beats unknown beats green).
    public static func worst(_ a: TrunkStatus, _ b: TrunkStatus) -> TrunkStatus {
        max(a, b)
    }

    /// The worst status in a collection. An EMPTY collection is `.unknown`, NOT
    /// `.green`: nothing was checked, so nothing can be certified. Green is a
    /// positive claim and must be earned — see THE BOUND. Defaulting emptiness to
    /// green was one of three ambient false-greens.
    public static func worst<S: Sequence>(of statuses: S) -> TrunkStatus where S.Element == TrunkStatus {
        statuses.max() ?? .unknown
    }

    /// DERIVE the discrete summary from a node's per-grammar readiness — the
    /// bridge from the B3 primitive (tracks) back to a single label for CLI/gate.
    ///
    /// Rules, honouring the model (any broken grammar → not universally ready;
    /// unprobed is not a hold):
    ///   - any participating grammar `.broken` → `.red`;
    ///   - else any grammar holds with a caution → `.yellow`;
    ///   - else at least one grammar holds cleanly → `.green`;
    ///   - else (no grammar was probed, or the node participates in none)
    ///     → `.unknown` — never a false green.
    ///
    /// Note a node can hold in one grammar and be broken in another: `.broken`
    /// dominates in this discrete summary (it isn't *universally* ready), even
    /// though the COLOUR still shows the holding grammar's chroma (the mix keeps
    /// more information than this label does — that is the point of the rework).
    public static func from(readiness: NodeReadiness) -> TrunkStatus {
        let verdicts = readiness.verdicts.values
        guard !verdicts.isEmpty else { return .unknown }

        if verdicts.contains(where: {
            if case .broken = $0 { return true }
            return false
        }) {
            return .red
        }

        let holds = verdicts.filter { $0.isHold }
        guard !holds.isEmpty else {
            // No broken, no holds → everything unprobed.
            return .unknown
        }

        if holds.contains(where: {
            if case .holds(let caution) = $0 { return caution }
            return false
        }) {
            return .yellow
        }
        return .green
    }
}
