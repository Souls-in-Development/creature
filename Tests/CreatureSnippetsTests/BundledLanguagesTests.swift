import Testing
@testable import CreatureSnippets

@Suite struct BundledLanguagesTests {
    @Test func loadsEveryBundledLanguageOffline() {
        let langs = BundledLanguages.bundled()
        // Every mainstream language ships in the resource — no toolchain required.
        #expect(langs.languageCount >= 40)
        // Spot-check across paradigms.
        #expect(langs.byName["python"]?.keywords.contains("lambda") == true)
        #expect(langs.byName["rust"]?.keywords.contains("impl") == true)
        #expect(langs.byName["haskell"]?.keywords.contains("where") == true)
        #expect(langs.byName["sql"] != nil)
        // Extension routing works.
        #expect(langs.language(forExtension: "rs") == "rust")
        #expect(langs.language(forExtension: "py") == "python")
        // A large union vocabulary.
        #expect(langs.allKeywords.count > 500)
    }

    @Test func bundlesCanonicalConstructSnippets() {
        let langs = BundledLanguages.bundled()
        // Snippets are the point — canonical constructs bundled per language.
        #expect(langs.snippetCount > 50)
        #expect(langs.languagesWithSnippets.count >= 40)
        // Full coverage: every language with vocab also ships construct snippets.
        #expect(Set(langs.snippetsByLanguage.keys) == Set(langs.byName.keys))
        #expect(langs.snippet("haskell", "case")?.contains("case") == true)
        #expect(langs.snippet("assembly", "syscall")?.contains("syscall") == true)
        #expect(langs.snippet("python", "function")?.contains("def ") == true)
        #expect(langs.snippet("rust", "match")?.contains("match") == true)
        #expect(langs.snippet("sql", "select")?.contains("SELECT") == true)
        #expect(langs.snippets(for: "swift")?["guard"] != nil)
        // Placeholders use ${...} fields.
        #expect(langs.snippet("go", "function")?.contains("${name}") == true)
    }
}
