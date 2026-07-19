import Testing
@testable import CreatureSnippets

@Suite struct SnippetRetrieverTests {
    let r = SnippetRetriever()

    @Test func retrievesExactVerifiedSnippetNotInvented() {
        // The snippet returned must be byte-for-byte the library's ground-truth, so a
        // plugged-in AI uses it verbatim rather than inventing syntax.
        let matches = r.retrieve("for loop", language: "rust")
        #expect(matches.contains { $0.construct == "for" })
        let forSnippet = matches.first { $0.construct == "for" }?.snippet
        #expect(forSnippet == r.languages.snippet("rust", "for"))
    }

    @Test func synonymsAndPhrasingResolveToConstructs() {
        // Natural phrasing → the right verified construct, any language.
        #expect(r.retrieve("error handling", language: "swift").contains { $0.construct == "try" || $0.construct == "guard" || $0.construct == "catch" } == true)
        #expect(r.retrieve("a method", language: "python").contains { $0.construct == "function" })
        #expect(r.retrieve("iterate", language: "go").contains { $0.construct == "for" })
    }

    @Test func shortTermsDoNotSubstringMatchConstructs() {
        // Regression: the 2-char term "in" used to substring-match "pr-IN-t", so
        // "for loop in rust" wrongly dragged in rust's `print`. Matching is exact
        // (plus a length-guarded prefix rule), never loose containment.
        let m = r.retrieve("for loop in rust")
        #expect(m.contains { $0.construct == "for" })
        #expect(!m.contains { $0.construct == "print" })
        // The prefix rule still catches plurals/gerunds.
        #expect(r.retrieve("functions in go").contains { $0.construct == "function" })
        #expect(r.retrieve("printing in go").contains { $0.construct == "print" })
    }

    @Test func queryNamesLanguageInline() {
        // "for loop in haskell" scopes without an explicit --lang.
        let matches = r.retrieve("case in haskell")
        #expect(matches.allSatisfy { $0.language == "haskell" })
        #expect(matches.contains { $0.construct == "case" })
    }

    @Test func contextBlockIsGroundedAndModelAgnostic() {
        let block = r.contextBlock(for: "class", language: "kotlin")
        #expect(block.contains("use these exactly"))
        #expect(block.contains("kotlin"))
        // Empty (not garbage) when nothing matches — callers can prepend unconditionally.
        #expect(r.contextBlock(for: "zzzznotathing", language: "nonexistent-lang").isEmpty)
    }

    @Test func worksAcrossEveryBundledLanguage() {
        // "any AI, all languages": every bundled language yields at least one snippet
        // when asked for its whole set by name.
        for lang in r.languages.byName.keys {
            #expect(!r.retrieve(lang).isEmpty, "no snippet retrievable for \(lang)")
        }
    }

    @Test func reachesHarvestedCorpusScopedByLanguage() {
        // The whole library, not just canonical constructs: a loaded harvested store is
        // searchable for real usages, scoped to the requested language.
        var store = SnippetStore(maxBytes: 1_000_000)
        store.add(id: "/pkg/sorting.rs", "fn demo() {\n    v.sort_unstable_by_key(|x| x.id);\n}\n")
        store.add(id: "/pkg/sorting.py", "def demo():\n    items.sort(key=lambda x: x.id)\n")
        let rr = SnippetRetriever(store: store)

        let rust = rr.retrieve("sort_unstable", language: "rust")
        let ex = rust.filter { $0.source == .example }
        // The match is now the BLOCK; the concrete line is a variant of it.
        #expect(ex.contains { $0.variants.contains { $0.contains("sort_unstable_by_key") } })
        #expect(ex.contains { $0.snippet.contains("${}") })
        // Scoped: the Python line must not leak into a Rust query.
        #expect(!ex.contains { $0.variants.contains { $0.contains("lambda") } })
        #expect(rr.contextBlock(for: "sort_unstable", language: "rust").contains("block ·"))
    }

    @Test func type2SiblingsCollapseToOneBlockWithVariations() {
        // Two virtualenvs: different names, different paths, one block. Retrieval must
        // return the shape once, carrying both bindings — not the same shape twice.
        var store = SnippetStore(maxBytes: 1_000_000)
        store.add(id: "/a.py", #"venv_alpha = create_env("/tmp/a")"# + "\n")
        store.add(id: "/b.py", #"venv_beta = create_env("/opt/b")"# + "\n")
        let rr = SnippetRetriever(store: store)

        let ex = rr.retrieve("create_env", language: "python").filter { $0.source == .example }
        #expect(ex.count == 1)                       // one block, not two lines
        #expect(ex.first?.variants.count == 2)       // two variations of it
        #expect(ex.first?.snippet.contains("${}") == true)
        // The searched term survives in the block rather than vanishing into a hole.
        #expect(ex.first?.snippet.contains("create_env") == true)

        let block = rr.contextBlock(for: "create_env", language: "python")
        #expect(block.contains("venv_alpha"))
        #expect(block.contains("venv_beta"))
    }

    @Test func harvestedSearchIgnoresConstructWordsAndLanguageNames() {
        // A pure construct query ("for loop in rust") must NOT drag in noisy harvested
        // lines just because they contain "for" or "rust" — canonical answers those.
        var store = SnippetStore(maxBytes: 1_000_000)
        store.add(id: "/pkg/a.rs", "    for x in xs { println!(\"{}\", x); }\n")
        let rr = SnippetRetriever(store: store)
        #expect(rr.retrieve("for loop in rust").allSatisfy { $0.source == .canonical })
    }
}
