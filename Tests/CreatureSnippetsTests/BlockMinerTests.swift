import Testing
import Foundation
@testable import CreatureSnippets

@Suite struct BlockMinerTests {
    // A 5-line block that recurs verbatim across many documents.
    private let commonBlock = """
    func setUp() {
        configure()
        connect()
        ready = true
    }

    """   // 5 lines incl. trailing blank

    @Test func surfacesACommonMultiLineBlock() {
        var store = SnippetStore(maxBytes: 10_000_000)
        // 10 docs, each = a unique preamble + the SAME 5-line block.
        for i in 0..<10 { store.add(id: "d\(i)", "// file \(i)\nlet unique\(i) = \(i)\n" + commonBlock) }

        let blocks = BlockMiner.commonBlocks(in: store, docIDs: (0..<10).map { "d\($0)" },
                                             length: 5, minFiles: 4, top: 10)
        #expect(!blocks.isEmpty)
        let top = blocks[0]
        #expect(top.files >= 4)                       // recurs across many documents
        #expect(top.text.contains("func setUp()"))    // it IS the common block
        #expect(top.text.contains("ready = true"))
        // Its identity is letter data — every line reference is a valid letter key.
        #expect(top.lineKeys.allSatisfy { LetterKey.decode($0) != nil })
    }

    @Test func ignoresBlankOnlyBlocks() {
        var store = SnippetStore(maxBytes: 10_000_000)
        for i in 0..<10 { store.add(id: "d\(i)", "x\(i)\n\n\n\n\n\n") }   // mostly blank
        let blocks = BlockMiner.commonBlocks(in: store, docIDs: (0..<10).map { "d\($0)" },
                                             length: 5, minFiles: 4, top: 10)
        #expect(blocks.allSatisfy { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }
}
