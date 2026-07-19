import Foundation
import CreatureSnippets

// `snippets` — harvest EVERY installed language's own library (read-only) into a
// lossless, letter-encoded snippet library, and SAVE it as a shippable file so the
// IDE ships the library instead of re-harvesting it. This is the LSP-replacement
// corpus: any language whose toolchain/library is present contributes.
//
//   snippets                       harvest all detected language roots, report
//   snippets --save <path>         harvest, then persist to <path> (shippable asset)
//   snippets --load <path>         load a saved library, report (proves lossless reload)
//   snippets <dir> [<dir> ...]     harvest specific directories instead of the defaults
//   snippets query <text> [--lang X] [--load <lib>]   grounded snippets for ANY plugged-in AI
//
// Zero external dependencies (CreatureSnippets is Foundation-only) — builds without MLX.

// `query` — the access layer any plugged-in AI uses. It does NOT invent syntax; it
// retrieves the exact verified snippets from the library and emits a grounded context
// block to prepend to any model's prompt. With `--load <lib>` it also searches the
// harvested real-code corpus (canonical constructs first, then real usages) so the AI
// reaches the WHOLE library. Same interface for every model; accuracy comes from
// grounding. Emits the block on stdout (empty exit 0 if nothing matched).
if CommandLine.arguments.dropFirst().first == "query" {
    var qargs = Array(CommandLine.arguments.dropFirst(2)), lang: String?, libPath: String?, terms: [String] = []
    var qi = 0
    while qi < qargs.count {
        switch qargs[qi] {
        case "--lang": qi += 1; if qi < qargs.count { lang = qargs[qi] }
        case "--load": qi += 1; if qi < qargs.count { libPath = qargs[qi] }
        default: terms.append(qargs[qi])
        }
        qi += 1
    }
    let query = terms.joined(separator: " ")
    let lib = try libPath.map { try SnippetStore.load(from: URL(fileURLWithPath: $0)) }
    let block = SnippetRetriever(store: lib).contextBlock(for: query, language: lang)
    if block.isEmpty {
        FileHandle.standardError.write("snippets: no verified snippet for \"\(query)\"\(lang.map { " (\($0))" } ?? "").\n".data(using: .utf8)!)
    } else {
        print(block, terminator: "")
    }
    exit(0)
}

let fm = FileManager.default
func mb(_ b: Int) -> String { String(format: "%.1f MB", Double(b) / 1_048_576) }
func add(_ path: String, _ roots: inout [String]) { if FileManager.default.fileExists(atPath: path) { roots.append(path) } }
func newest(in parent: String) -> String? { (try? FileManager.default.contentsOfDirectory(atPath: parent))?.sorted(by: >).first }

/// Detect the installed language libraries — as many languages as this machine has.
/// The design supports ALL languages (any extension, any root); this fills the
/// defaults from whatever toolchains are present. Absent languages are skipped.
func defaultRoots() -> [String] {
    var r: [String] = []
    // Python stdlib (newest framework version) + homebrew fallback.
    if let v = newest(in: "/Library/Frameworks/Python.framework/Versions") {
        add("/Library/Frameworks/Python.framework/Versions/\(v)/lib/python\(v)", &r)
    }
    if let d = newest(in: "/opt/homebrew/lib"), d.hasPrefix("python") { add("/opt/homebrew/lib/\(d)", &r) }
    // C / C++ / ObjC / Metal — macOS SDK headers + homebrew + /usr/include.
    add("/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include", &r)
    add("/opt/homebrew/include", &r)
    add("/usr/include", &r)
    // TypeScript / JavaScript.
    add("/opt/homebrew/lib/node_modules/typescript/lib", &r)
    // Swift stdlib interfaces.
    add("/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift", &r)
    // Ruby stdlib.
    add("/opt/homebrew/opt/ruby/lib/ruby", &r)
    if let v = newest(in: "/usr/lib/ruby") { add("/usr/lib/ruby/\(v)", &r) }
    // Go.
    add("/opt/homebrew/opt/go/libexec/src", &r)
    add("/usr/local/go/src", &r)
    // Rust std source.
    let rustup = (NSHomeDirectory() as NSString).appendingPathComponent(".rustup/toolchains")
    if let t = newest(in: rustup) { add("\(rustup)/\(t)/lib/rustlib/src/rust/library", &r) }
    // Homebrew per-language extras (php, lua, perl are commonly under here).
    add("/opt/homebrew/share", &r)
    return r
}

// Parse args: --save PATH, --load PATH, or positional directories.
var savePath: String?, loadPath: String?, dirs: [String] = []
var argv = Array(CommandLine.arguments.dropFirst()); var i = 0
while i < argv.count {
    switch argv[i] {
    case "--save": i += 1; if i < argv.count { savePath = argv[i] }
    case "--load": i += 1; if i < argv.count { loadPath = argv[i] }
    default: dirs.append(argv[i])
    }
    i += 1
}

var store: SnippetStore

if let loadPath {
    store = try SnippetStore.load(from: URL(fileURLWithPath: loadPath))
    print("snippets — loaded \(store.docCount) documents from \(loadPath)")
    print("  \(mb(store.storedBytes)) stored  (\(store.uniqueLines) unique lines, letter-keyed)")
} else {
    let roots = dirs.isEmpty ? defaultRoots() : dirs
    guard !roots.isEmpty else {
        FileHandle.standardError.write("snippets: no language libraries found. Pass directories, or install toolchains.\n".data(using: .utf8)!)
        exit(1)
    }
    store = SnippetStore(maxBytes: 500_000_000)
    let result = CorpusHarvester.harvest(roots: roots, into: &store, fileCap: 50_000)
    print("snippets — harvested \(result.filesRead) files from \(roots.count) language roots, wrote \(result.filesWritten) (read-only)")
    print("  raw \(mb(result.rawBytes))  ->  stored \(mb(store.storedBytes))  (\(store.uniqueLines) unique lines, letter-keyed)")
    if let savePath {
        try store.save(to: URL(fileURLWithPath: savePath))
        let bytes = (try? fm.attributesOfItem(atPath: savePath)[.size] as? Int) ?? nil
        print("  saved -> \(savePath)  (\(bytes.map(mb) ?? "?"))  — shippable, no re-harvest at launch")
    }
}

let vocab = BundledLanguages.bundled()
print("  bundled offline (no toolchain): \(vocab.snippetCount) construct snippets across \(vocab.languagesWithSnippets.count) languages, \(vocab.languageCount) languages' vocab (\(vocab.allKeywords.count) keywords)")

// Type-2 clone classes: the same block wearing different names. The content-addressed
// store cannot see these (it interns exact content); the template index can.
let classes = TemplateIndex.cloneClasses(in: store, keywords: vocab.allKeywords, minVariants: 2, top: 6)
if !classes.isEmpty {
    let variantTotal = classes.reduce(0) { $0 + $1.variants }
    print("  \(classes.count) top Type-2 clone classes (\(variantTotal) distinct lines collapse onto them):\n")
    for (n, c) in classes.enumerated() {
        print("#\(n + 1)  \(c.variants) variants · \(c.holeCount) holes")
        print("     block  \(SnippetNormalizer.render(c.template).trimmingCharacters(in: .whitespacesAndNewlines).prefix(96))")
        for ex in c.examples.prefix(2) { print("     e.g.   \(ex.prefix(96))") }
        print("")
    }
}

let blocks = BlockMiner.commonBlocks(in: store, docIDs: store.documentIDs, length: 5, minFiles: 4, top: 8)
print("  \(blocks.count) common code blocks:\n")
for (n, b) in blocks.enumerated() {
    print("#\(n + 1)  \(b.occurrences)× across \(b.files) files   keys \(b.lineKeys)")
    for line in b.text.split(separator: "\n", omittingEmptySubsequences: false).prefix(3) {
        print("     | \(line)")
    }
    print("")
}
