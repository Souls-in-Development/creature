import Foundation

/// Read-only harvest of code files into a `SnippetStore`.
///
/// STRICTLY READ-ONLY: it opens files only for reading (`String(contentsOf:)`) and
/// NEVER writes, moves, or deletes anything under the corpus roots. `filesWritten` is
/// always 0 — it exists so callers/tests can assert the guarantee. Any persistence of
/// the store belongs elsewhere, in the store's own data file, never in the corpus.
public enum CorpusHarvester {
    /// Code extensions harvested from the languages' own libraries — ALL the common
    /// languages, because this is meant to cover what an LSP would (any language whose
    /// toolchain/library is present on the machine contributes; absent ones just don't).
    public static let defaultExtensions: Set<String> = [
        "swift","swiftinterface","py","pyi","ts","tsx","js","jsx","mjs","cjs",
        "java","kt","kts","scala","groovy","gradle","cs","fs","vb",
        "m","mm","c","cc","cpp","cxx","h","hpp","hxx","metal",
        "rs","go","rb","php","lua","pl","pm","r","sh","bash","zsh",
        "hs","clj","cljs","ex","exs","erl","jl","zig","dart","nim","cr","d","ml","mli","sql"
    ]

    /// Directory names skipped entirely (build artifacts, VCS, third-party, test noise).
    public static let skipDirectories: Set<String> =
        [".build",".git","node_modules","DerivedData","site-packages","test","tests",
         "__pycache__","lib2to3","idlelib",".swiftpm","Pods"]

    public struct Result: Sendable {
        public var filesRead = 0
        /// ALWAYS 0 — this harvester never writes to the corpus. Assert on it.
        public var filesWritten = 0
        public var rawBytes = 0
    }

    /// Walk `roots` read-only, feeding each code file's text into `store` (id = file path).
    /// Stops after `fileCap` files. Unreadable/binary files are skipped, never written.
    @discardableResult
    public static func harvest(roots: [String], into store: inout SnippetStore,
                               extensions: Set<String> = defaultExtensions,
                               fileCap: Int = 20_000) -> Result {
        var result = Result()
        let fm = FileManager.default
        for root in roots {
            if result.filesRead >= fileCap { break }
            guard let en = fm.enumerator(at: URL(fileURLWithPath: root),
                                         includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
            for case let url as URL in en {
                if result.filesRead >= fileCap { break }
                var isDir: ObjCBool = false
                fm.fileExists(atPath: url.path, isDirectory: &isDir)
                if isDir.boolValue {
                    if skipDirectories.contains(url.lastPathComponent) { en.skipDescendants() }
                    continue
                }
                guard extensions.contains(url.pathExtension.lowercased()) else { continue }
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }  // READ ONLY
                result.rawBytes += text.utf8.count
                store.add(id: url.path, text)
                result.filesRead += 1
            }
        }
        return result
    }
}
