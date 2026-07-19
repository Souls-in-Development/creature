import Foundation

/// A standalone, dependency-free, lossless, size-capped snippet store.
///
///  • Hierarchy: document → ordered LETTER-KEY references → unique line content.
///  • Referencing / dedup: each distinct line is interned ONCE and addressed by a
///    letter key (see `LetterKey`); a document holds only its sequence of keys.
///  • Lossless: lines keep their trailing "\n", so concatenating a document's
///    referenced lines reproduces the input byte-for-byte.
///  • Size ceiling: a hard byte budget on unique content held; when exceeded, the
///    least-recently-added documents are evicted, decrementing their lines' refcounts;
///    a line at refcount 0 is freed. Common lines (shared by many docs) survive.
///  • No model, no grammar, no external dependencies. Foundation only.
public struct SnippetStore: Sendable {
    private var keyOf: [String: String] = [:]     // line content -> letter key
    private var lineOf: [String: String] = [:]    // letter key -> line content (stored once)
    private var refs: [String: Int] = [:]         // letter key -> refcount
    private var nextIndex = 0
    private var docs: [String: [String]] = [:]    // doc id -> ordered letter-key references
    private var order: [String] = []              // insertion order, oldest first
    public private(set) var storedBytes = 0
    public private(set) var evicted = 0
    public let maxBytes: Int

    public init(maxBytes: Int) { self.maxBytes = maxBytes }

    // Split into lines that KEEP their newline, so join == original (lossless).
    private func splitLossless(_ text: String) -> [String] {
        var out: [String] = []; var cur = ""
        for ch in text { cur.append(ch); if ch == "\n" { out.append(cur); cur = "" } }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    private mutating func intern(_ line: String) -> String {
        if let k = keyOf[line] { refs[k, default: 0] += 1; return k }
        let k = LetterKey.encode(nextIndex); nextIndex += 1
        keyOf[line] = k; lineOf[k] = line; refs[k] = 1
        storedBytes += line.utf8.count
        return k
    }

    @discardableResult
    public mutating func add(id: String, _ text: String) -> String {
        if docs[id] != nil { remove(id: id) }          // replace-in-place
        docs[id] = splitLossless(text).map { intern($0) }
        order.append(id)
        while storedBytes > maxBytes && order.count > 1 && order.first! != id {
            remove(id: order.first!); evicted += 1
        }
        return id
    }

    /// Lossless reconstruction; `nil` if the document was evicted / never stored.
    public func get(id: String) -> String? {
        guard let keys = docs[id] else { return nil }
        return keys.reduce(into: "") { $0 += lineOf[$1]! }
    }

    public mutating func remove(id: String) {
        guard let keys = docs[id] else { return }
        for k in keys {
            refs[k, default: 1] -= 1
            if refs[k]! <= 0 {
                storedBytes -= (lineOf[k]?.utf8.count ?? 0)
                if let c = lineOf[k] { keyOf[c] = nil }
                lineOf[k] = nil; refs[k] = nil
            }
        }
        docs[id] = nil
        order.removeAll { $0 == id }
    }

    public var uniqueLines: Int { lineOf.count }
    public var totalReferences: Int { docs.values.reduce(0) { $0 + $1.count } }
    public var docCount: Int { docs.count }
    /// The ids of every document currently stored — the handles to feed `BlockMiner`
    /// or to reconstruct. Ids are whatever the caller/harvester supplied (for the
    /// harvester that is the filesystem-resolved path), so look documents up by these
    /// rather than by a separately-constructed path.
    public var documentIDs: [String] { Array(docs.keys) }
    public func keys(ofDoc id: String) -> [String]? { docs[id] }
    public func line(forKey key: String) -> String? { lineOf[key] }
    public func containsLine(_ line: String) -> Bool { keyOf[line] != nil }
    /// Every interned line key — the handles `TemplateIndex` groups into Type-2 classes.
    public var allLineKeys: [String] { Array(lineOf.keys) }

    /// Search the harvested corpus: stored lines containing `needle` (case-insensitive),
    /// optionally restricted to documents whose id passes `docFilter` (used to scope by
    /// language via file extension). Returns `(documentID, trimmed line)` pairs, deduped
    /// by line content, capped at `limit`. This is what makes the harvested real-code
    /// snippets reachable to retrieval — actual usages, not just canonical constructs.
    public func searchLines(containing needle: String, limit: Int = 8,
                            where docFilter: (String) -> Bool = { _ in true }) -> [(doc: String, line: String)] {
        let n = needle.lowercased()
        guard !n.isEmpty else { return [] }
        var out: [(doc: String, line: String)] = []
        var seen = Set<String>()
        for id in order where docFilter(id) {
            guard let keys = docs[id] else { continue }
            for k in keys {
                guard let content = lineOf[k] else { continue }
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.count >= 2, trimmed.lowercased().contains(n), !seen.contains(trimmed) else { continue }
                seen.insert(trimmed)
                out.append((doc: id, line: trimmed))
                if out.count >= limit { return out }
            }
        }
        return out
    }

    // MARK: - Persistence (lossless, Foundation-only, zero dependencies)

    /// The unique line table + each document's key sequence are ALL that's needed to
    /// reconstruct everything; refcounts / storedBytes / LRU order are recomputed on
    /// load. Written as JSON (Foundation-only, human-inspectable).
    private struct Archive: Codable {
        let lines: [String: String]     // letter key -> content
        let docs: [String: [String]]    // doc id -> ordered key references
        let nextIndex: Int
        let maxBytes: Int
    }

    /// Persist the store to `url` (atomic). The written file, reloaded, reconstructs
    /// every document byte-for-byte — so the harvested library ships as a built asset
    /// instead of being re-harvested at every launch.
    public func save(to url: URL) throws {
        let archive = Archive(lines: lineOf, docs: docs, nextIndex: nextIndex, maxBytes: maxBytes)
        try JSONEncoder().encode(archive).write(to: url, options: .atomic)
    }

    /// Load a store previously written by `save(to:)`. Reconstruction is lossless.
    public static func load(from url: URL) throws -> SnippetStore {
        let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: url))
        var store = SnippetStore(maxBytes: archive.maxBytes)
        store.lineOf = archive.lines
        store.nextIndex = archive.nextIndex
        for (key, content) in archive.lines {
            store.keyOf[content] = key
            store.storedBytes += content.utf8.count
        }
        store.docs = archive.docs
        for (id, keys) in archive.docs {
            store.order.append(id)
            for k in keys { store.refs[k, default: 0] += 1 }
        }
        return store
    }
}
