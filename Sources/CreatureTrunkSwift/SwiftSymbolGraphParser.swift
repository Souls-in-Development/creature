import Foundation

/// Parses the `.symbols.json` files emitted by `swiftc -emit-symbol-graph`.
/// The symbol graph is JSON, one object per file, with a `symbols` array.
/// Each symbol carries a USR (`identifier.precise`) and a location
/// (`location.uri` as a `file://` URI, `location.position.line` as 0-based
/// line, `location.position.character` as 0-based character).
///
/// We convert the URI to a filesystem path, line to 1-based, and build a
/// spatial index for fast "which symbol contains this line?" lookup.
public enum SwiftSymbolGraphParser {
    
    /// One symbol entry from the graph.
    public struct Symbol: Sendable, Equatable {
        public let usr: String
        public let name: String
        public let filePath: String
        public let line: Int        // 1-based
        public let character: Int   // 1-based
        
        public init(usr: String, name: String, filePath: String, line: Int, character: Int) {
            self.usr = usr
            self.name = name
            self.filePath = filePath
            self.line = line
            self.character = character
        }
    }
    
    /// Parse one `.symbols.json` file into `Symbol` entries.
    /// Returns empty array on missing file or parse failure (caller decides
    /// whether to degrade).
    public static func parseSymbolGraph(at path: String) -> [Symbol] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return [] }
        
        struct TopLevel: Codable {
            struct SymbolEntry: Codable {
                struct Identifier: Codable { let precise: String }
                struct Names: Codable { let title: String }
                struct Location: Codable {
                    let uri: String
                    struct Position: Codable { let line: Int; let character: Int }
                    let position: Position
                }
                let identifier: Identifier
                let names: Names
                let location: Location
            }
            let symbols: [SymbolEntry]
        }
        
        guard let top = try? JSONDecoder().decode(TopLevel.self, from: data) else { return [] }
        
        return top.symbols.map { entry in
            let filePath = entry.location.uri
                .replacingOccurrences(of: "file://", with: "")
                .removingPercentEncoding ?? entry.location.uri
            // swiftc symbol graph uses 0-based line/character; diagnostics use 1-based.
            return Symbol(
                usr: entry.identifier.precise,
                name: entry.names.title,
                filePath: filePath,
                line: entry.location.position.line + 1,
                character: entry.location.position.character + 1
            )
        }
    }
    
    /// Build a spatial index from a list of symbols.
    /// For each file, symbols are sorted by line. A diagnostic at a given line
    /// is attributed to the last symbol whose start line is ≤ the diagnostic line.
    /// This gives the innermost containing declaration for the common case.
    public struct SpatialIndex: Sendable {
        public let symbolsByFile: [String: [Symbol]]
        
        public init(symbols: [Symbol]) {
            var byFile: [String: [Symbol]] = [:]
            for symbol in symbols {
                byFile[symbol.filePath, default: []].append(symbol)
            }
            self.symbolsByFile = byFile.mapValues { $0.sorted { $0.line < $1.line } }
        }
        
        /// Find the USR of the innermost symbol containing `line` in `filePath`.
        /// Returns `nil` if no symbol in that file starts at or before the line.
        public func usrFor(filePath: String, line: Int) -> String? {
            guard let symbols = symbolsByFile[filePath] else { return nil }
            // Find the last symbol whose start line ≤ diagnostic line.
            // In a future pass we can refine with end-line inference from the
            // next symbol or node spans; this is sufficient for the Phase 1 gate.
            return symbols.last { $0.line <= line }?.usr
        }
    }
}
