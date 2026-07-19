import Foundation

/// The access layer that makes the library usable by ANY plugged-in AI, accurately.
///
/// The whole point: a model must not *invent* a snippet (that is where hallucination
/// lives) — it *retrieves* the verified one from the library and uses it verbatim. So
/// this returns EXACT library snippets (bundled canonical constructs — authored, correct)
/// and formats them as a model-agnostic **grounded context block** that any AI can be fed
/// before it answers. Same interface for every model; accuracy comes from grounding, not
/// from the model. Zero external dependencies.
public struct SnippetRetriever: Sendable {
    public let languages: BundledLanguages
    /// The harvested real-code corpus (loaded from a saved `.snip` asset), or nil. When
    /// present, retrieval spans it too — so a plugged-in AI reaches the WHOLE library,
    /// not just the bundled canonical constructs.
    public let store: SnippetStore?
    /// Union vocabulary, hoisted out of the hot path — `SnippetNormalizer` needs it per line.
    private let keywordSet: Set<String>

    public init(languages: BundledLanguages = .bundled(), store: SnippetStore? = nil) {
        self.languages = languages
        self.store = store
        self.keywordSet = languages.allKeywords
    }

    /// Where a match came from: an authored canonical construct, or a real harvested usage.
    public enum Source: Sendable, Equatable { case canonical, example }

    public struct Match: Sendable, Equatable {
        public let language: String
        public let construct: String   // canonical: construct name; example: source-file basename
        /// The block. For canonical, the authored template. For a harvested example, the
        /// α-normalized template — so both sources speak in the same shape.
        public let snippet: String
        public let source: Source
        /// Concrete lines that instantiate `snippet`: the variations and modifiers the
        /// documents supplied. Empty for canonical constructs (nothing has bound them yet).
        public let variants: [String]

        public init(language: String, construct: String, snippet: String, source: Source, variants: [String] = []) {
            self.language = language
            self.construct = construct
            self.snippet = snippet
            self.source = source
            self.variants = variants
        }
    }

    /// Common phrasings → construct names, so "give me a loop / error handling / a method"
    /// resolves to the right verified constructs regardless of wording.
    static let synonyms: [String: [String]] = [
        "loop": ["for","while","foreach","forin","do"],
        "iterate": ["for","foreach","forin"],
        "method": ["function","method","sub","def","proc","defun"],
        "func": ["function"],
        "def": ["function"],
        "error": ["try","error","catch","rescue","except"],
        "exception": ["try","catch","rescue"],
        "handle": ["try","catch"],
        "output": ["print"],
        "log": ["print"],
        "write": ["print"],
        "object": ["class","struct","type","record"],
        "type": ["type","struct","class","interface"],
        "conditional": ["if","match","case","cond","switch"],
        "branch": ["if","match","case","switch"],
        "include": ["import","include","use","using","require","with","open"],
        "module": ["import","module","ns","namespace"],
        "query": ["select"],
    ]

    /// Retrieve verified snippets matching `query`, optionally scoped to `language`. If the
    /// query names a language (e.g. "for loop in rust"), that scopes it automatically.
    public func retrieve(_ query: String, language: String? = nil, limit: Int = 12) -> [Match] {
        let q = query.lowercased()
        let rawTerms = q.split { !$0.isLetter }.map(String.init).filter { !$0.isEmpty }
        // Construct matching drops single letters (noise); language detection keeps them,
        // so single-char language names (c, r, d) still resolve.
        var wanted = Set(rawTerms.filter { $0.count > 1 })
        for term in wanted { if let syns = Self.synonyms[term] { wanted.formUnion(syns) } }

        let langFilter = language?.lowercased() ?? rawTerms.first(where: { languages.byName[$0] != nil })
        let langs = langFilter.map { [$0] } ?? Array(languages.snippetsByLanguage.keys).sorted()

        // 1) Canonical constructs (authored, always-accurate) — the primary, ranked first.
        var canonical: [Match] = []
        for lang in langs {
            guard let snips = languages.snippets(for: lang) else { continue }
            for (name, snippet) in snips.sorted(by: { $0.key < $1.key }) {
                let n = name.lowercased()
                // Exact match (synonyms already expanded `wanted` to construct names), plus a
                // length-guarded prefix rule for plurals/gerunds ("functions", "printing").
                // NOT loose substring matching: that let the 2-char term "in" match "pr-in-t".
                let hit = wanted.contains(n)
                    || wanted.contains { $0.count >= 4 && ($0.hasPrefix(n) || n.hasPrefix($0)) }
                if hit {
                    canonical.append(Match(language: lang, construct: name, snippet: snippet, source: .canonical))
                }
            }
        }
        // Query is essentially just a language name (no construct term beyond it) → return
        // that language's full set. A symbol query (e.g. "searchLines") is NOT this — it
        // should fall through to harvested examples, not dump every construct.
        let constructTerms = wanted.subtracting(langFilter.map { [$0] } ?? [])
        if canonical.isEmpty, constructTerms.isEmpty, let langFilter, let snips = languages.snippets(for: langFilter) {
            canonical = snips.sorted { $0.key < $1.key }.map { Match(language: langFilter, construct: $0.key, snippet: $0.value, source: .canonical) }
        }

        // 2) Harvested real-code usages (only if a library is loaded). Search on the
        //    identifier-like terms — not construct words (canonical covers those) and not
        //    the language name (it scopes, it isn't a needle) — so this surfaces genuine
        //    API/usage examples rather than flooding on "for"/"if".
        var examples: [Match] = []
        if let store {
            let constructWords = Set(Self.synonyms.keys).union(Self.synonyms.values.flatMap { $0 })
            let needle = rawTerms
                .filter { $0.count >= 3 && !constructWords.contains($0) && languages.byName[$0] == nil }
                .max(by: { $0.count < $1.count })
            if let needle {
                let exts = langFilter.flatMap { languages.byName[$0]?.extensions }
                let docFilter: (String) -> Bool = { path in
                    guard let exts, !exts.isEmpty else { return true }
                    let p = path.lowercased()
                    return exts.contains { p.hasSuffix(".\($0)") }
                }
                // Group hits by their block. Two lines that differ only in names are the
                // same construct (Type-2), so they collapse to one match carrying both as
                // variations — rather than repeating the shape once per rename.
                var byBlock: [String: (lang: String, file: String, lines: [String])] = [:]
                var blockOrder: [String] = []
                for hit in store.searchLines(containing: needle, limit: 12, where: docFilter) {
                    let ext = (hit.doc as NSString).pathExtension
                    let lang = langFilter ?? languages.language(forExtension: ext) ?? "code"
                    let base = (hit.doc as NSString).lastPathComponent
                    // Pin the searched term: it is what makes this block the block asked for.
                    let normalized = SnippetNormalizer.normalize(hit.line, keywords: keywordSet, pinning: needle)
                    // Fall back to the raw line when there is nothing to abstract.
                    let block = (normalized?.holeCount ?? 0) > 0
                        ? SnippetNormalizer.render(normalized!.template)
                        : hit.line
                    if byBlock[block] == nil {
                        blockOrder.append(block)
                        byBlock[block] = (lang, base, [])
                    }
                    byBlock[block]!.lines.append(hit.line)
                }
                for block in blockOrder.prefix(4) {
                    let g = byBlock[block]!
                    examples.append(Match(
                        language: g.lang,
                        construct: g.file,
                        snippet: block,
                        source: .example,
                        variants: Array(g.lines.prefix(3))
                    ))
                }
            }
        }

        return Array(canonical.prefix(limit)) + examples
    }

    /// A model-agnostic grounded context block: the exact verified snippets, labelled, to
    /// prepend to ANY model's prompt so it answers from ground-truth rather than inventing.
    /// Empty when nothing matched (so callers can prepend unconditionally).
    public func contextBlock(for query: String, language: String? = nil, limit: Int = 12) -> String {
        let matches = retrieve(query, language: language, limit: limit)
        guard !matches.isEmpty else { return "" }
        var out = "Verified code snippets from the library — use these exactly, do not invent syntax:\n\n"
        for m in matches {
            let tag = m.source == .canonical ? m.construct : "block · \(m.construct)"
            out += "[\(m.language) · \(tag)]\n\(m.snippet)\n"
            // The block is the shape; the variants show how real code binds its holes.
            for v in m.variants { out += "  ↳ \(v)\n" }
            out += "\n"
        }
        return out
    }
}
