import Testing
import Foundation
@testable import CreatureSnippets

@Suite struct CorpusHarvesterTests {
    private func makeCorpus() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("creature-snippets-corpus-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "func a() {}\nlet x = 1\n".write(to: root.appendingPathComponent("A.swift"), atomically: true, encoding: .utf8)
        try "def b():\n    return 2\n".write(to: root.appendingPathComponent("b.py"), atomically: true, encoding: .utf8)
        try "# not code, must be ignored\n".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        // A .build dir that MUST be skipped entirely.
        let build = root.appendingPathComponent(".build", isDirectory: true)
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        try "func ignored() {}\n".write(to: build.appendingPathComponent("Ignored.swift"), atomically: true, encoding: .utf8)
        return root
    }

    /// THE SAFETY GATE: harvesting must not modify, move, or delete ANY source file.
    @Test func harvestIsStrictlyReadOnly() throws {
        let root = try makeCorpus()
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default

        // Snapshot every file's modification date + exact bytes BEFORE.
        func snapshot() throws -> [String: (Date, Data)] {
            var s: [String: (Date, Data)] = [:]
            let en = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey])!
            for case let u as URL in en where !(try u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false) {
                let mtime = (try u.resourceValues(forKeys: [.contentModificationDateKey])).contentModificationDate!
                s[u.path] = (mtime, try Data(contentsOf: u))
            }
            return s
        }
        let before = try snapshot()

        var store = SnippetStore(maxBytes: 10_000_000)
        let result = CorpusHarvester.harvest(roots: [root.path], into: &store)

        let after = try snapshot()
        #expect(result.filesWritten == 0)              // the harvester never writes to the corpus
        #expect(before.keys == after.keys)             // no file created or deleted
        for (path, (mtime, bytes)) in before {
            #expect(after[path]!.0 == mtime)           // untouched modification time
            #expect(after[path]!.1 == bytes)           // untouched bytes
        }
    }

    @Test func readsCodeFilesSkipsNonCodeAndBuildDirs() throws {
        let root = try makeCorpus()
        defer { try? FileManager.default.removeItem(at: root) }
        var store = SnippetStore(maxBytes: 10_000_000)
        let result = CorpusHarvester.harvest(roots: [root.path], into: &store)

        #expect(result.filesRead == 2)                 // A.swift + b.py, NOT README.md, NOT .build
        // Look up by the store's own id (filesystem-resolved path), not a re-constructed
        // one — the enumerator resolves symlinks (/var → /private/var).
        let aID = store.documentIDs.first { $0.hasSuffix("A.swift") }
        #expect(aID != nil)
        #expect(store.get(id: aID!) == "func a() {}\nlet x = 1\n")   // lossless on a harvested file
    }
}
