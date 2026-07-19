import Foundation

/// The compiler's verdict on cited source. `clean` defaults to false and is only ever set
/// by an affirmative pass — never by the absence of diagnostics. THE BOUND.
public struct VerifierVerdict: Sendable, Equatable {
    /// True iff the toolchain type-checked the source successfully.
    public let clean: Bool
    /// Error messages, verbatim from the producer, to hand back for re-citation.
    public let messages: [String]
    /// Non-nil iff the verifier could not run at all. Never `clean` when set.
    public let unavailableReason: String?

    public init(clean: Bool, messages: [String], unavailableReason: String? = nil) {
        self.clean = clean
        self.messages = messages
        self.unavailableReason = unavailableReason
    }

    /// The honest-degrade constructor: nothing checked, so nothing certified.
    public static func unavailable(_ reason: String) -> VerifierVerdict {
        VerifierVerdict(clean: false, messages: [], unavailableReason: reason)
    }
}

/// Adjudicates cited source. A key-emitting unconscious is worthless without one: citation
/// buys well-formed *blocks*, and this is the only thing that can catch bad *agreement*
/// between them (a name that doesn't exist, a type that doesn't fit).
///
/// A protocol because `CreatureSpine` has no dependencies — the real `swiftc`-backed
/// implementation lives in `CreatureKeys`.
public protocol CodeVerifier: Sendable {
    /// Lowercased grammar identity, e.g. `"swift"`.
    var language: String { get }
    func verify(source: String) async -> VerifierVerdict
}
