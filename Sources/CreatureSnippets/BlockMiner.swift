import Foundation

/// Surfaces COMMON MULTI-LINE CODE BLOCKS from a `SnippetStore` — grammar-free:
/// pure repeat detection over the stored line-key sequences, no parser and no model.
/// A block recurring across many documents is exactly the reusable snippet
/// "everyone wants." Each block is identified by the LETTER KEYS of its lines.
public enum BlockMiner {
    public struct Block: Sendable {
        public let lineKeys: [String]   // the block's line references (letter data)
        public let text: String         // reconstructed block content (lossless slice)
        public let occurrences: Int      // times it appears across the corpus
        public let files: Int            // distinct documents it appears in
    }

    /// Find contiguous `length`-line blocks recurring in at least `minFiles` distinct
    /// documents, ranked by occurrences (most common first, capped at `top`). Blocks
    /// that are entirely blank/whitespace are skipped.
    public static func commonBlocks(in store: SnippetStore, docIDs: [String],
                                    length: Int = 5, minFiles: Int = 4, top: Int = 20) -> [Block] {
        var count: [String: Int] = [:]
        var sample: [String: [String]] = [:]
        var files: [String: Set<Int>] = [:]

        for (fi, id) in docIDs.enumerated() {
            guard let keys = store.keys(ofDoc: id), keys.count >= length else { continue }
            for i in 0...(keys.count - length) {
                let block = Array(keys[i..<i+length])
                let isBlank = block.allSatisfy {
                    (store.line(forKey: $0) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                if isBlank { continue }
                let sig = block.joined(separator: " ")      // letter-key signature of the block
                count[sig, default: 0] += 1
                if sample[sig] == nil { sample[sig] = block }
                files[sig, default: []].insert(fi)
            }
        }

        return count
            .filter { (files[$0.key]?.count ?? 0) >= minFiles }
            .sorted { $0.value > $1.value }
            .prefix(top)
            .map { (sig, occ) in
                let block = sample[sig]!
                let text = block.reduce(into: "") { $0 += store.line(forKey: $1) ?? "" }
                return Block(lineKeys: block, text: text, occurrences: occ, files: files[sig]!.count)
            }
    }
}
