import Testing
@testable import CreatureSnippets

@Suite struct SnippetNormalizerTests {
    let kw = BundledLanguages.bundled().allKeywords

    /// Losslessness is the whole contract: abstracting names must never corrupt the code.
    @Test func roundTripsExactlyOnAwkwardLines() {
        let lines = [
            "    let x = foo(bar, 42)\n",
            "v.sort_unstable_by_key(|x| x.id);",
            #"print("hello \"world\"", 3.14)"#,
            "for item in collection { process(item) }",
            "x = 0xFF + 1_000 + 1e9",
            "const name = require('os').tmpdir();",
            "",
            "\t\t}\n",
        ]
        for line in lines {
            guard let n = SnippetNormalizer.normalize(line, keywords: kw) else {
                Issue.record("refused to normalize \(line)"); continue
            }
            #expect(SnippetNormalizer.denormalize(n) == line, "round-trip failed for \(line)")
        }
    }

    @Test func keywordsStayStructureNamesBecomeHoles() {
        let n = SnippetNormalizer.normalize("for item in xs { }", keywords: kw)!
        // `for` and `in` are keywords — they are the block. `item`/`xs` are modifiers.
        #expect(n.template.hasPrefix("for "))
        #expect(n.bindings == ["item", "xs"])
    }

    @Test func literalsBecomeHoles() {
        let n = SnippetNormalizer.normalize(#"loadThing("os")"#, keywords: kw)!
        #expect(n.bindings == ["loadThing", #""os""#])
        #expect(SnippetNormalizer.denormalize(n) == #"loadThing("os")"#)
    }

    /// Keywords are the UNION across all 43 bundled languages, because a line key is
    /// interned globally and may be shared by documents in different languages — there
    /// is no single language to scope to. So a name that is a keyword *somewhere*
    /// (`require` in Crystal/Perl/Lua) stays literal even in a language where it isn't.
    /// That costs deduplication and never costs correctness, which is the trade we want.
    @Test func unionKeywordsKeepSomeNamesLiteral() {
        let n = SnippetNormalizer.normalize(#"require("os")"#, keywords: kw)!
        #expect(n.bindings == [#""os""#])            // `require` did NOT become a hole
        #expect(n.template.hasPrefix("require("))
        #expect(SnippetNormalizer.denormalize(n) == #"require("os")"#)  // still exact
    }

    /// The claim under test: different name, different path — still a virtual environment.
    @Test func twoVirtualenvsShareOneTemplate() {
        let a = SnippetNormalizer.normalize(#"venv_a = create_env("/tmp/a", clear=1)"#, keywords: kw)!
        let b = SnippetNormalizer.normalize(#"venv_b = create_env("/opt/b", clear=1)"#, keywords: kw)!
        #expect(a.template == b.template)     // same block
        #expect(a.bindings != b.bindings)     // different modifiers
        // And each still reconstructs its own document exactly.
        #expect(SnippetNormalizer.denormalize(a) == #"venv_a = create_env("/tmp/a", clear=1)"#)
        #expect(SnippetNormalizer.denormalize(b) == #"venv_b = create_env("/opt/b", clear=1)"#)
    }

    /// The searched term is structure. Abstracting it hides the answer inside a hole.
    @Test func pinnedNeedleStaysLiteral() {
        let plain = SnippetNormalizer.normalize("os.makedirs(d)", keywords: kw)!
        #expect(!plain.template.contains("makedirs"))          // over-abstracted

        let pinned = SnippetNormalizer.normalize("os.makedirs(d)", keywords: kw, pinning: "makedirs")!
        #expect(pinned.template.contains("makedirs"))
        #expect(pinned.bindings == ["os", "d"])
        #expect(SnippetNormalizer.denormalize(pinned) == "os.makedirs(d)")   // still exact

        // Substring match: pinning "unstable" keeps the whole `sort_unstable_by_key` token.
        let sub = SnippetNormalizer.normalize("v.sort_unstable_by_key(f)", keywords: kw, pinning: "unstable")!
        #expect(sub.template.contains("sort_unstable_by_key"))
        #expect(SnippetNormalizer.denormalize(sub) == "v.sort_unstable_by_key(f)")
    }

    @Test func substitutesCallerSuppliedBindings() {
        let n = SnippetNormalizer.normalize("os.makedirs(d)", keywords: kw)!
        // Rebinding the same block with different modifiers — still the same block.
        #expect(SnippetNormalizer.substitute(template: n.template, bindings: ["shutil", "rmtree", "path"])
                == "shutil.rmtree(path)")
        // Fewer bindings than holes leaves the trailing holes unfilled (caller must check arity).
        #expect(SnippetNormalizer.substitute(template: n.template, bindings: []) == "\u{0}.\u{0}(\u{0})")
        // denormalize still agrees with substitute.
        #expect(SnippetNormalizer.denormalize(n) == "os.makedirs(d)")
    }

    @Test func refusesLinesContainingTheHoleMarker() {
        #expect(SnippetNormalizer.normalize("a\u{0}b", keywords: kw) == nil)
    }

    @Test func rendersHolesReadably() {
        let n = SnippetNormalizer.normalize("let x = 1", keywords: kw)!
        #expect(SnippetNormalizer.render(n.template).contains("${}"))
    }
}

@Suite struct TemplateIndexTests {
    let kw = BundledLanguages.bundled().allKeywords

    @Test func groupsType2ClonesTheExactStoreCannotSee() {
        var store = SnippetStore(maxBytes: 1_000_000)
        store.add(id: "/a.py", #"venv_a = create_env("/tmp/a")"# + "\n")
        store.add(id: "/b.py", #"venv_b = create_env("/opt/b")"# + "\n")

        // The content-addressed store sees two unrelated lines...
        #expect(store.uniqueLines == 2)
        // ...the template index sees one block with two variants.
        let classes = TemplateIndex.cloneClasses(in: store, keywords: kw)
        #expect(classes.count == 1)
        #expect(classes.first?.variants == 2)
        #expect((classes.first?.holeCount ?? 0) >= 3)
    }

    @Test func skipsCommentsAndProse() {
        #expect(!TemplateIndex.looksLikeCode("// Copyright 2019 The LLVM Authors"))
        #expect(!TemplateIndex.looksLikeCode("# this is a note"))
        #expect(!TemplateIndex.looksLikeCode("just some words"))
        #expect(TemplateIndex.looksLikeCode("let x = foo(1)"))
    }

    /// A bare assignment is a shape; a call is a block. The threshold has to keep the
    /// virtualenv case (`${} = ${}(${})`, mass 3) and drop `${} = ${}` (mass 1).
    @Test func structuralMassSeparatesBlocksFromShapes() {
        #expect(TemplateIndex.structuralMass("\u{0} = \u{0}") == 1)
        #expect(TemplateIndex.structuralMass("\u{0}: \u{0},") == 2)
        #expect(TemplateIndex.structuralMass("\u{0} = \u{0}(\u{0})") == 3)   // the virtualenv
        #expect(TemplateIndex.structuralMass("def \u{0}(self):") == 10)
    }

    @Test func shapelessClassesAreFilteredButBlocksSurvive() {
        var store = SnippetStore(maxBytes: 1_000_000)
        store.add(id: "/a.py", "alpha = one\nbeta = two\n")              // `${} = ${}` — mass 1
        store.add(id: "/b.py", "def alpha(self):\ndef beta(self):\n")    // `def ${}(self):` — mass 10

        let blocks = TemplateIndex.cloneClasses(in: store, keywords: kw)
        #expect(blocks.count == 1)
        #expect(SnippetNormalizer.render(blocks[0].template).contains("def"))

        // With no threshold, the shapeless class comes back too.
        #expect(TemplateIndex.cloneClasses(in: store, keywords: kw, minStructuralMass: 0).count == 2)
    }

    @Test func identicalLinesAreNotAClass() {
        var store = SnippetStore(maxBytes: 1_000_000)
        store.add(id: "/a.py", "x = f(1)\n")
        store.add(id: "/b.py", "x = f(1)\n")   // interned once — Type-1, not a variation
        #expect(store.uniqueLines == 1)
        #expect(TemplateIndex.cloneClasses(in: store, keywords: kw).isEmpty)
    }
}
