import Testing
import Foundation
@testable import CreatureSnippets

@Suite struct SnippetStoreTests {
    // Synthetic "code" with heavy line-level repetition, like real code.
    private func doc(_ n: Int) -> String {
        """
        import Foundation
        import Foundation
        struct Thing\(n): Codable {
            let id: Int
            guard let x = maybe else { return }
            return x
        }
        """
    }

    @Test func reconstructsEveryDocumentByteForByte() {
        var store = SnippetStore(maxBytes: 1_000_000)
        var originals: [String: String] = [:]
        for i in 0..<200 { let id = "doc\(i)"; let t = doc(i); originals[id] = t; store.add(id: id, t) }
        for (id, text) in originals { #expect(store.get(id: id) == text) }   // lossless
    }

    @Test func sharedLinesAreInternedOnce() {
        var store = SnippetStore(maxBytes: 1_000_000)
        for i in 0..<200 { store.add(id: "doc\(i)", doc(i)) }
        // Many shared lines (import/guard/return/brace) → far fewer unique than total.
        #expect(Double(store.totalReferences) / Double(store.uniqueLines) > 3.0)
    }

    @Test func referencesAreLetterDataOnly() {
        var store = SnippetStore(maxBytes: 1_000_000)
        store.add(id: "d", doc(1))
        for key in store.keys(ofDoc: "d")! {
            #expect(LetterKey.decode(key) != nil)   // every reference is a valid letter key
        }
    }

    @Test func ceilingEvictsRareDocsButKeepsCommonLines() {
        var store = SnippetStore(maxBytes: 2_000)      // ~2 KB hard cap
        for i in 0..<2000 { store.add(id: "d\(i)", doc(i)) }
        #expect(store.storedBytes <= 2_000)            // never exceeds the ceiling
        #expect(store.evicted > 0)                     // rare/old docs were evicted
        #expect(store.containsLine("import Foundation\n"))   // the COMMON line survived
        #expect(store.get(id: "d1999") == doc(1999))         // a retained doc is still lossless
    }

    @Test func savesAndReloadsLosslessly() throws {
        var store = SnippetStore(maxBytes: 1_000_000)
        var originals: [String: String] = [:]
        for i in 0..<50 { let id = "doc\(i)"; let t = doc(i); originals[id] = t; store.add(id: id, t) }

        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("snip-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try store.save(to: url)
        let reloaded = try SnippetStore.load(from: url)

        // Every document reconstructs byte-for-byte AFTER a save/reload cycle — so the
        // harvested library ships as a built file, not re-harvested each launch.
        for (id, text) in originals { #expect(reloaded.get(id: id) == text) }
        #expect(reloaded.uniqueLines == store.uniqueLines)
        #expect(reloaded.docCount == store.docCount)
    }
}
