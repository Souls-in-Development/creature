import Foundation

/// Which eigenstate a partner's response came back in.
///
/// The two partners run on the same prompt, in the same moment, with no barrier between
/// them. What tells them apart is not *who answered* but *in what basis they answered*:
/// the conscious speaks in words, the unconscious speaks in code. `.code` carries the
/// resolved source, which for a key script is the text the store resolved — not the
/// citation the model actually emitted.
public enum ResponseBasis: Sendable, Equatable {
    case words
    case code(String)

    /// The resolved source when this is the code phase, else nil.
    public var codePayload: String? {
        if case .code(let source) = self { return source }
        return nil
    }
}

/// Decides the basis of a response. Kept a protocol because `CreatureSpine` has no
/// dependencies and must not import the snippet library: the real, key-aware detector
/// lives downstream in `CreatureKeys`.
public protocol BasisDetector: Sendable {
    func basis(of response: String) -> ResponseBasis
}

/// The historical detector — a response is code iff it contains a fence. A string sniff,
/// and the thing `KeyScriptBasisDetector` supersedes. Retained as the fallback for any
/// partner that does not speak in keys, so plain models keep working unchanged.
public struct CodeFenceBasisDetector: BasisDetector {
    public init() {}
    public func basis(of response: String) -> ResponseBasis {
        response.contains("```") ? .code(response) : .words
    }
}
