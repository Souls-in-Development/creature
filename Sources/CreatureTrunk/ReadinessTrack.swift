import Foundation
import CreatureSpine

/// The verdict ONE grammar reaches over ONE node — the atom of B3 readiness.
///
/// This is deliberately NOT a traffic-light. Readiness is not a scalar per
/// node; it is a *running per-grammar signal* (see the B3 plan §0/§1). Each
/// participating language grammar reaches its own verdict here, and those
/// verdicts become interleaved colour tracks mixed additively — white emerges
/// when every present grammar holds, a subset chroma when only some do, a
/// shifted colour where one broke.
///
/// Three honest states, and what each contributes to the additive mix:
///
/// - `holds`   — this grammar was PROBED over this node and it checks out. A
///               **full-energy** track (its language hue at
///               `TrunkColour.forLanguage` saturation×value) — it participates
///               in "holds."
/// - `broken`  — this grammar was PROBED and a hard error is attributed to this
///               node. A **zero-energy** track — it FALLS OUT of the mix, so the
///               running colour shifts toward the grammars that still hold.
///               "Broken in Swift but fine in Python" = Swift dropping out,
///               Python standing.
/// - `unprobed`— this grammar's probe never ran (toolchain absent / degraded /
///               no probe for this language). Also a **zero-energy** track:
///               present but weightless, the honest "we didn't check this
///               grammar." It never fakes a hold and never fakes white.
///
/// Note `broken` and `unprobed` are both zero-energy in the mix (both remove a
/// grammar from "holds"), but they are DIFFERENT facts and are kept distinct so
/// a discrete summary can tell "checked and failing" from "never checked" (see
/// `NodeReadiness.summary` / `TrunkStatus`). A warning is a *lesser* issue that
/// still holds structurally — it is carried as `holds` with a `.caution` flag
/// rather than dropping the grammar out, so a warned-but-compiling node keeps
/// its hue.
public enum GrammarVerdict: Sendable, Hashable, Codable {
    /// Probed and checks out (optionally with a non-fatal caution / warning).
    case holds(caution: Bool)
    /// Probed and a hard error is attributed to this node — drops out of the mix.
    case broken
    /// Never probed — present but weightless; never a hold, never white.
    case unprobed

    /// Convenience: a clean hold with no caution.
    public static let holds = GrammarVerdict.holds(caution: false)

    /// True iff this grammar contributes a holding (weighted) track to the mix.
    public var isHold: Bool {
        if case .holds = self { return true }
        return false
    }

    /// True iff this grammar was actually probed (holds or broken), as opposed
    /// to never-checked. Distinguishes the two zero-energy cases for summaries.
    public var wasProbed: Bool {
        switch self {
        case .holds, .broken: return true
        case .unprobed:       return false
        }
    }
}

/// The readiness of ONE node across every language grammar that PARTICIPATES in
/// it (the languages it has a channel in). This is the B3 primitive that
/// replaces a flat per-node status enum: readiness is stored as the set of
/// per-grammar verdicts, and a node's single-glance colour is the *additive
/// mix* of those verdicts' colour tracks (see `ReadinessMixer`).
///
/// A node with an empty `verdicts` map participates in no grammar (e.g. a
/// synthetic node with no language channel) — it contributes nothing and mixes
/// to a neutral / unprobed colour, never a false hold.
public struct NodeReadiness: Sendable, Hashable, Codable {
    /// language name (lowercased, e.g. "swift", "python") → that grammar's
    /// verdict over this node.
    public let verdicts: [String: GrammarVerdict]

    public init(verdicts: [String: GrammarVerdict]) {
        self.verdicts = verdicts
    }

    /// An empty readiness — no participating grammar.
    public static let none = NodeReadiness(verdicts: [:])

    /// The languages that participate in this node, in a stable (sorted) order
    /// so the mix and any rendering are deterministic.
    public var languages: [String] { verdicts.keys.sorted() }
}
