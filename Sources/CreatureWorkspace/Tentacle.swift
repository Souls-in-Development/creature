import Foundation
import CreatureTrunk
import CreatureTrunkSwift
import CreatureTrunkPython
import CreatureSnippets

/// Which language tentacle handles a file. Swift and Python each have a real,
/// AST-based tentacle (SwiftSyntax; Python's own `ast`). Every other language in
/// the bundled catalogue is handled by `.universal` — a shared, regex-level
/// structural indexer (`CodeIngester`) that places the file in the trunk and
/// links it across languages by declaration shape, without an AST or a compiler
/// probe behind it.
///
/// Adding a *high-fidelity* tentacle (a real TypeScript or Rust AST) means a new
/// case here; until then, those languages are already covered structurally by
/// `.universal` rather than being invisible to the workspace.
public enum Tentacle {
    case swift
    case python
    /// Any catalogued language without a dedicated AST tentacle. `language` is
    /// the catalogue name (e.g. "rust", "typescript").
    case universal(language: String)

    /// The bundled language catalogue (keywords + extensions), loaded once. Used
    /// to resolve an unknown extension to a language name.
    private static let catalog = BundledLanguages.bundled()

    public init?(filePath: String) {
        let ext = URL(fileURLWithPath: filePath).pathExtension.lowercased()
        switch ext {
        case "swift": self = .swift
        case "py": self = .python
        default:
            // Any other catalogued extension → the universal regex tentacle.
            // Unknown extensions (no catalogue entry) are genuinely unindexable,
            // so return nil and let the workspace skip them.
            guard let language = Tentacle.catalog.language(forExtension: ext) else {
                return nil
            }
            self = .universal(language: language)
        }
    }

    public func index(source: String, module: String) -> [TrunkNode] {
        switch self {
        case .swift: return SwiftIndexer.index(source: source, module: module)
        case .python: return PythonIndexer.index(source: source, module: module)
        case .universal(let language):
            return [CodeIngester.ingest(source: source, language: language, path: [module])]
        }
    }

    public func indexWithStatus(source: String, module: String) -> (nodes: [TrunkNode], status: [String: TrunkStatus]) {
        switch self {
        case .swift: return SwiftIndexer.indexWithStatus(source: source, module: module)
        case .python: return PythonIndexer.indexWithStatus(source: source, module: module)
        case .universal(let language):
            // Leaf status is `.unknown` at index time — the regex scan cannot
            // certify the file, and any real verdict comes LATER from a
            // `CompileProbe` over the workspace (see WorkspaceProbe /
            // ExternalToolProbe). Never `.green` here: that would be a false
            // green before any tool has looked.
            let node = CodeIngester.ingest(source: source, language: language, path: [module])
            return (nodes: [node], status: [node.id: .unknown])
        }
    }

    public var language: String {
        switch self {
        case .swift: return "swift"
        case .python: return "python"
        case .universal(let language): return language
        }
    }

    public func indexWithBridge(source: String, module: String, file: String? = nil) -> (nodes: [TrunkNode], status: [String: TrunkStatus], edges: [UnresolvedEdge]) {
        switch self {
        case .swift: return SwiftIndexer.indexWithBridge(source: source, module: module, file: file)
        case .python: return PythonIndexer.indexWithBridge(source: source, module: module)
        case .universal(let language):
            // Set the node's file span from `file` — this is what lets a
            // CompileProbe later attribute a real verdict (green/red) to this
            // node by matching `probedFiles`. v0: no dependency edges from the
            // regex path (a header scan does not resolve imports/calls); nodes
            // still link across languages by truthKey, which is structural.
            let node = CodeIngester.ingest(source: source, language: language, path: [module], file: file)
            return (nodes: [node], status: [node.id: .unknown], edges: [])
        }
    }
}
