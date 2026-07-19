import Testing
import CreatureSpine
import CreatureSnippets
@testable import CreatureKeys

@Suite struct KeyScriptBasisDetectorTests {
    private func fixture() -> (SnippetStore, String) {
        var store = SnippetStore(maxBytes: 1_000_000)
        store.add(id: "/a.py", "os.makedirs(d)\n")
        return (store, store.allLineKeys.first!)
    }

    @Test func aKeyScriptIsTheCodeBasisAndResolvesToSource() {
        let (store, key) = fixture()
        let d = KeyScriptBasisDetector(store: store)
        #expect(d.basis(of: "^\(key)") == .code("os.makedirs(d)\n"))
    }

    @Test func bindingsAreResolvedNotEchoed() {
        let (store, key) = fixture()
        let d = KeyScriptBasisDetector(store: store)
        #expect(d.basis(of: "^\(key) | shutil | rmtree | path") == .code("shutil.rmtree(path)\n"))
    }

    @Test func proseIsTheWordBasis() {
        let (store, _) = fixture()
        #expect(KeyScriptBasisDetector(store: store).basis(of: "because X follows Y") == .words)
    }

    /// A partner that does not speak keys must keep working: fall back to the fence sniff.
    @Test func fallsBackToCodeFenceForNonKeyResponses() {
        let (store, _) = fixture()
        let d = KeyScriptBasisDetector(store: store)
        #expect(d.basis(of: "```swift\nlet x = 1\n```") == .code("```swift\nlet x = 1\n```"))
    }

    /// The bijection guard: an unresolvable citation is NOT silently treated as code.
    @Test func unknownKeyDoesNotBecomeCode() {
        let (store, _) = fixture()
        let d = KeyScriptBasisDetector(store: store)
        #expect(d.basis(of: "^zzzz") == .words)
    }

    @Test func arityMismatchDoesNotBecomeCode() {
        let (store, key) = fixture()
        let d = KeyScriptBasisDetector(store: store)
        #expect(d.basis(of: "^\(key) | only") == .words)   // block has 3 holes
    }
}
