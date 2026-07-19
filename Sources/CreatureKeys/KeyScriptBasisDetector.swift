import Foundation
import CreatureSpine
import CreatureSnippets

/// The real basis detector: the unconscious speaks in citations, the conscious in words.
///
/// Replaces the `contains("```")` sniff. A response is the code phase iff it parses as a
/// key script AND every citation resolves — an unknown key or a bad arity is refused
/// outright and falls through to the word basis, never quietly emitted as code. Any
/// partner that does not speak keys keeps working via the code-fence fallback.
public struct KeyScriptBasisDetector: BasisDetector {
    private let store: SnippetStore
    private let keywords: Set<String>
    private let fallback: any BasisDetector

    public init(
        store: SnippetStore,
        languages: BundledLanguages = .bundled(),
        fallback: any BasisDetector = CodeFenceBasisDetector()
    ) {
        self.store = store
        self.keywords = languages.allKeywords
        self.fallback = fallback
    }

    public func basis(of response: String) -> ResponseBasis {
        guard KeyScript.isKeyScript(response),
              let instructions = KeyScript.parse(response),
              let source = try? KeyScript.resolve(instructions, store: store, keywords: keywords)
        else {
            return fallback.basis(of: response)
        }
        return .code(source)
    }
}
