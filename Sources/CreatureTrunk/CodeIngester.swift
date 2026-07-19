import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
// Apple's own cross-platform implementation of the same API (swift-crypto).
// Only SHA-256 is used, and it is source-identical on both.
import Crypto
#endif

/// v0 minimal ingester: turns one source file's text into a `TrunkNode`.
///
/// Builds:
/// - Channel 1: the raw source text, labelled with `language`, coloured with
///   that language's chroma.
/// - Channel 0: a normalized structural *skeleton* of the source — the
///   declaration shapes (kind + name + arity) found at the top level, with
///   language-specific syntax stripped away. Coloured white.
/// - `TrunkCoordinate`: built from `path` plus the skeleton, with `truthKey`
///   set to a hash of the Channel-0 skeleton text.
///
/// HONESTY (read before assuming this does more than it does): this is a
/// v0 normalizer, not a semantic equivalence engine. It recognizes a handful
/// of common declaration keywords per language (`func`/`class`/`struct` for
/// Swift; `def`/`class` for Python) via regex, extracts name + naive arity
/// (comma-count in the parameter list), and renders them into one
/// language-agnostic line per declaration: `"<kind> <name>/<arity>"`. Two
/// snippets that declare the same-shaped function in different languages
/// *can* produce an identical skeleton (see `CodeIngesterTests` for a
/// worked example) — but this is shape-matching on declaration signatures,
/// not proof of behavioural equivalence, and it will miss or misjudge
/// anything beyond simple top-level declarations (nested scopes, overloads,
/// default arguments, decorators/attributes, generics, etc.). Real
/// cross-language equivalence normalization is future work.
public enum CodeIngester {

    /// Ingest one source file into a `TrunkNode`.
    ///
    /// - Parameters:
    ///   - source: raw source text.
    ///   - language: language name for Channel 1 (e.g. "swift", "python").
    ///   - path: structural path (module → … → file), used both for the
    ///     `TrunkCoordinate.path` and as part of the node id.
    ///   - file: absolute path of the source on disk, when known. It becomes the
    ///     node's `SourceSpan.file` — REQUIRED for a `CompileProbe` to attribute
    ///     a real toolchain verdict back to this node (see `DiagnosticReducer`).
    ///     Without it the node can never be certified green: it has no file for
    ///     `probedFiles` to match, so it stays unknown — honest, but unprovable.
    public static func ingest(source: String, language: String, path: [String], file: String? = nil) -> TrunkNode {
        let skeleton = normalize(source: source, language: language)
        let truthKey = truthHash(of: skeleton)

        let coordinate = TrunkCoordinate(
            path: path,
            kind: "file",
            truthKey: truthKey
        )

        let channel0 = TrunkChannel(index: 0, language: "rosetta", content: skeleton)
        let channel1 = TrunkChannel(index: 1, language: language, content: source)

        let id = "\(path.joined(separator: "/"))#\(language)"

        // A whole-file span: a file-level node covers all its lines, so any
        // diagnostic the probe reports (whatever line) attributes to it.
        let span: SourceSpan? = file.map { path in
            let lineCount = max(1, source.split(separator: "\n", omittingEmptySubsequences: false).count)
            return SourceSpan(file: path, startLine: 1, endLine: lineCount)
        }

        return TrunkNode(id: id, coordinate: coordinate, channels: [channel0, channel1], span: span)
    }

    /// Produce the Channel-0 structural skeleton for `source` in `language`.
    /// One line per recognized top-level declaration: `"<kind> <name>/<arity>"`.
    /// Unrecognized languages fall back to an empty skeleton (no declarations
    /// extracted) rather than guessing.
    public static func normalize(source: String, language: String) -> String {
        let declarations = DeclarationExtractor.extract(source: source, language: language)
        return declarations
            .map { "\($0.kind) \($0.name)/\($0.arity)" }
            .sorted()
            .joined(separator: "\n")
    }

    /// SHA-256 of the skeleton text, hex-encoded. Stable across runs/platforms.
    public static func truthHash(of skeleton: String) -> String {
        let digest = SHA256.hash(data: Data(skeleton.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// One recognized top-level declaration shape.
struct DeclarationShape {
    let kind: String   // "func", "class", "struct", ...
    let name: String
    let arity: Int
}

/// Language-specific extraction of top-level declaration shapes via simple
/// regex matching — deliberately not a real parser. See `CodeIngester`'s
/// doc comment for what this does and does not guarantee.
enum DeclarationExtractor {
    static func extract(source: String, language: String) -> [DeclarationShape] {
        switch language.lowercased() {
        case "swift":
            return extractSwift(source: source)
        case "python":
            return extractPython(source: source)
        default:
            // Every other catalogued language goes through the generic,
            // keyword-driven extractor. It is deliberately cross-language: the
            // point of the trunk is that a Rust `fn add(a, b)` and a Swift
            // `func add(a:b:)` both skeleton to `func add/2` and so share a
            // truthKey. Lower fidelity than a real AST walk (it sees only
            // top-level, single-line declaration headers), which is exactly why
            // nodes it produces are never certified green — see `Tentacle`'s
            // `.universal` status.
            return extractGeneric(source: source)
        }
    }

    /// Language-agnostic declaration extraction: recognise the declaration
    /// *headers* common across the C-family, ML-family, and def/fn-style
    /// languages by their keyword, and normalise them into the same
    /// `<kind> <name>/<arity>` skeleton the Swift/Python extractors emit.
    ///
    /// This is intentionally syntactic and shallow. It matches a declaration
    /// keyword, a name, and (for callables) a single-line parenthesised
    /// parameter list. It does not parse bodies, nested scopes, generics, or
    /// multi-line signatures — a real per-language AST would. It is the honest
    /// floor: enough structure to place a file in the trunk and link it across
    /// languages by shape, never enough to claim the file is correct.
    private static func extractGeneric(source: String) -> [DeclarationShape] {
        var shapes: [DeclarationShape] = []

        // Callable declarations across languages: function/func/fn/def/fun/sub/
        // proc(edure)/method/defn/defun. Name in group 1, params in group 2.
        shapes += matches(
            in: source,
            pattern: #"(?m)\b(?:function|func|fn|def|defn|defun|fun|sub|proc|procedure|method)\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)"#,
            kind: "func"
        )

        // Type/scope declarations across languages. The keyword becomes the
        // kind, so a Kotlin `interface` and a Rust `trait` stay distinguishable
        // in the skeleton while both being recognised as declarations.
        let typeKeywords = [
            "class", "struct", "interface", "trait", "enum", "record",
            "object", "protocol", "actor", "union", "contract", "namespace",
            "module", "package", "impl", "type",
        ]
        for keyword in typeKeywords {
            shapes += matches(
                in: source,
                pattern: #"(?m)\b"# + keyword + #"\s+([A-Za-z_][A-Za-z0-9_]*)"#,
                kind: keyword,
                arityGroup: nil
            )
        }

        return shapes
    }

    /// Matches `func name(...)`, `class Name`, `struct Name`, `enum Name`.
    private static func extractSwift(source: String) -> [DeclarationShape] {
        var shapes: [DeclarationShape] = []

        shapes += matches(
            in: source,
            pattern: #"func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)"#,
            kind: "func"
        )
        shapes += matches(
            in: source,
            pattern: #"\bclass\s+([A-Za-z_][A-Za-z0-9_]*)"#,
            kind: "class",
            arityGroup: nil
        )
        shapes += matches(
            in: source,
            pattern: #"\bstruct\s+([A-Za-z_][A-Za-z0-9_]*)"#,
            kind: "struct",
            arityGroup: nil
        )
        shapes += matches(
            in: source,
            pattern: #"\benum\s+([A-Za-z_][A-Za-z0-9_]*)"#,
            kind: "enum",
            arityGroup: nil
        )
        return shapes
    }

    /// Matches `def name(...)`, `class Name`.
    private static func extractPython(source: String) -> [DeclarationShape] {
        var shapes: [DeclarationShape] = []

        shapes += matches(
            in: source,
            pattern: #"def\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)"#,
            kind: "func"
        )
        shapes += matches(
            in: source,
            pattern: #"\bclass\s+([A-Za-z_][A-Za-z0-9_]*)"#,
            kind: "class",
            arityGroup: nil
        )
        return shapes
    }

    /// Run a regex over `source`, extracting a name (group 1) and, if
    /// `arityGroup` is provided, a parameter-list group whose comma count
    /// (naive — does not understand nested generics/brackets) gives arity.
    /// Declarations without a parameter list default to arity 0.
    private static func matches(
        in source: String,
        pattern: String,
        kind: String,
        arityGroup: Int? = 2
    ) -> [DeclarationShape] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(source.startIndex..<source.endIndex, in: source)
        let results = regex.matches(in: source, range: nsRange)

        return results.compactMap { match -> DeclarationShape? in
            guard let nameRange = Range(match.range(at: 1), in: source) else { return nil }
            let name = String(source[nameRange])

            var arity = 0
            if let arityGroup, match.numberOfRanges > arityGroup,
               let paramsRange = Range(match.range(at: arityGroup), in: source) {
                let params = String(source[paramsRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                arity = params.isEmpty ? 0 : params.split(separator: ",").count
            }

            return DeclarationShape(kind: kind, name: name, arity: arity)
        }
    }
}
