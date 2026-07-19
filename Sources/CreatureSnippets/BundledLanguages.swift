import Foundation

/// The bundled "language itself" layer, shipped as resources with the module (no
/// toolchain needed): per-language **snippets** (canonical constructs — how you write a
/// function, class, loop, error-handling) plus keywords + file extensions. This data is
/// kilobytes, so it's bundled for the languages directly rather than harvested. Pairs
/// with the harvested code snippets (the "snip library", `SnippetStore`): bundled
/// snippets + harvested snippets = the LSP-replacement corpus. Zero external deps.
public struct BundledLanguages: Sendable {
    public struct Language: Codable, Sendable {
        public let extensions: [String]
        public let keywords: [String]
    }

    /// language name → its vocab (keywords + extensions), from `languages.json`.
    public let byName: [String: Language]
    /// language name → construct name ("function","class","for",…) → snippet template,
    /// from `snippets.json`. Templates use `${placeholder}` fields.
    public let snippetsByLanguage: [String: [String: String]]

    public init(byName: [String: Language], snippetsByLanguage: [String: [String: String]] = [:]) {
        self.byName = byName
        self.snippetsByLanguage = snippetsByLanguage
    }

    /// Load the datasets shipped with the module. Returns empty only if a resource is
    /// missing/corrupt (a packaging error, not a normal runtime state).
    public static func bundled() -> BundledLanguages {
        func loadJSON<T: Decodable>(_ name: String, as: T.Type) -> T? {
            guard let url = Bundle.module.url(forResource: name, withExtension: "json"),
                  let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(T.self, from: data)
        }
        let langs = loadJSON("languages", as: [String: Language].self) ?? [:]
        let snips = loadJSON("snippets", as: [String: [String: String]].self) ?? [:]
        return BundledLanguages(byName: langs, snippetsByLanguage: snips)
    }

    public var languageCount: Int { byName.count }
    /// The union vocabulary — every keyword across every bundled language, deduped.
    public var allKeywords: Set<String> { Set(byName.values.flatMap { $0.keywords }) }
    /// The language a file extension belongs to (first match), or nil if unknown.
    public func language(forExtension ext: String) -> String? {
        let e = ext.lowercased()
        return byName.first { $0.value.extensions.contains(e) }?.key
    }

    // MARK: - Snippets

    /// The construct snippets for a language ("function" → template, …), or nil.
    public func snippets(for language: String) -> [String: String]? { snippetsByLanguage[language] }
    /// One construct's snippet template for a language, e.g. `snippet("python", "for")`.
    public func snippet(_ language: String, _ construct: String) -> String? {
        snippetsByLanguage[language]?[construct]
    }
    /// Total snippet templates bundled across all languages.
    public var snippetCount: Int { snippetsByLanguage.values.reduce(0) { $0 + $1.count } }
    /// Languages that currently ship construct snippets (extensible — one entry each).
    public var languagesWithSnippets: [String] { Array(snippetsByLanguage.keys) }
}
