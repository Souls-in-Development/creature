import Testing
@testable import CreatureSnippets

@Suite struct KeyScriptParseTests {
    @Test func parsesCiteBindAndGen() {
        let script = """
        ^abc
        ^de | os | d
        + let x = 1
        """
        let instructions = KeyScript.parse(script)
        #expect(instructions == [
            .cite(key: "abc"),
            .bind(key: "de", bindings: ["os", "d"]),
            .gen(text: "let x = 1"),
        ])
    }

    @Test func ignoresBlankLines() {
        #expect(KeyScript.parse("\n^abc\n\n") == [.cite(key: "abc")])
    }

    @Test func rejectsNonKeyAlphabet() {
        #expect(KeyScript.parse("^ABC") == nil)      // uppercase is not the LetterKey alphabet
        #expect(KeyScript.parse("^ab1") == nil)      // digits are not either
        #expect(KeyScript.parse("^") == nil)         // empty key
    }

    @Test func rejectsUnknownInstructionLines() {
        #expect(KeyScript.parse("hello there") == nil)
        #expect(KeyScript.parse("^abc\nrandom prose") == nil)
    }

    @Test func isKeyScriptRequiresAtLeastOneCitation() {
        #expect(KeyScript.isKeyScript("^abc"))
        #expect(KeyScript.isKeyScript("^ab | x"))
        #expect(!KeyScript.isKeyScript("+ just generated text"))   // no citation → not the key basis
        #expect(!KeyScript.isKeyScript("here is some prose"))
        #expect(!KeyScript.isKeyScript(""))
    }

    @Test func bindingsAreTrimmedAndMayNotBeEmpty() {
        #expect(KeyScript.parse("^ab |  os  | d ") == [.bind(key: "ab", bindings: ["os", "d"])])
        #expect(KeyScript.parse("^ab | | d") == nil)     // empty binding
    }
}

@Suite struct KeyScriptResolveTests {
    let kw = BundledLanguages.bundled().allKeywords

    private func storeWith(_ id: String, _ text: String) -> SnippetStore {
        var s = SnippetStore(maxBytes: 1_000_000)
        s.add(id: id, text)
        return s
    }

    @Test func citeEmitsStoredLineVerbatim() throws {
        let store = storeWith("/a.py", "os.makedirs(d)\n")
        let key = store.allLineKeys.first!
        let out = try KeyScript.resolve([.cite(key: key)], store: store, keywords: kw)
        #expect(out == "os.makedirs(d)\n")
    }

    @Test func bindRefillsTheBlocksHoles() throws {
        let store = storeWith("/a.py", "os.makedirs(d)\n")
        let key = store.allLineKeys.first!
        // Block is ${}.${}(${}) — three holes.
        let out = try KeyScript.resolve([.bind(key: key, bindings: ["shutil", "rmtree", "path"])],
                                        store: store, keywords: kw)
        #expect(out == "shutil.rmtree(path)\n")
    }

    @Test func genEmitsLiteralText() throws {
        let store = storeWith("/a.py", "x = 1\n")
        let out = try KeyScript.resolve([.gen(text: "let y = 2")], store: store, keywords: kw)
        #expect(out == "let y = 2\n")
    }

    /// The bijection guard: a key that is not in the store is refused, never guessed.
    @Test func unknownKeyThrows() {
        let store = storeWith("/a.py", "x = 1\n")
        #expect(throws: KeyScript.Failure.unknownKey("zzzz")) {
            try KeyScript.resolve([.cite(key: "zzzz")], store: store, keywords: kw)
        }
    }

    @Test func arityMismatchThrows() {
        let store = storeWith("/a.py", "os.makedirs(d)\n")
        let key = store.allLineKeys.first!
        #expect(throws: KeyScript.Failure.arityMismatch(key: key, expected: 3, got: 1)) {
            try KeyScript.resolve([.bind(key: key, bindings: ["only"])], store: store, keywords: kw)
        }
    }

    @Test func multipleInstructionsConcatenateAsLines() throws {
        var store = SnippetStore(maxBytes: 1_000_000)
        store.add(id: "/a.py", "import os\nos.makedirs(d)\n")
        let keys = store.allLineKeys.sorted()
        let importKey = keys.first { store.line(forKey: $0)!.contains("import") }!
        let callKey = keys.first { store.line(forKey: $0)!.contains("makedirs") }!

        let out = try KeyScript.resolve(
            [.cite(key: importKey), .bind(key: callKey, bindings: ["os", "makedirs", "target"])],
            store: store, keywords: kw
        )
        #expect(out == "import os\nos.makedirs(target)\n")
    }
}
