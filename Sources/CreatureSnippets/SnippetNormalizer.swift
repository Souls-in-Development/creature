import Foundation

/// Lexical α-normalization: turn a concrete line into a **template plus bindings**.
///
/// `venv_a = create(path_a)` and `venv_b = create(path_b)` are different strings but the
/// same block — Roy & Cordy's Type-2 clone (identical modulo identifier and literal names).
/// `SnippetStore` interns exact content, so it sees them as two unrelated lines. This
/// recovers the shape: the template is the block, the bindings are the variables and
/// modifiers that belong to the document.
///
/// No parser, no grammar, no model. A token becomes a hole when it is an identifier that
/// is not a keyword of ANY bundled language, or a numeric/string literal. Keywords,
/// punctuation and whitespace stay literal. The rule is deliberately conservative:
/// keeping a token in the template only costs deduplication, it can never corrupt the
/// reconstruction — `denormalize(normalize(x)) == x` always.
public enum SnippetNormalizer {
    /// Hole marker. NUL does not occur in source text; a line containing one is refused
    /// rather than round-tripped unsafely.
    public static let hole: Character = "\u{0}"

    public struct Normalized: Sendable, Equatable {
        public let template: String    // holes as `hole`
        public let bindings: [String]  // in hole order; the "variations and modifiers"
        public var holeCount: Int { bindings.count }
    }

    /// `nil` when the line already contains the hole marker (cannot round-trip safely).
    ///
    /// `pinning` keeps any identifier containing that substring literal. When a caller has
    /// searched for `makedirs`, abstracting `makedirs` into a hole would hide the very
    /// thing that was asked about — the searched term is structure, not a modifier.
    public static func normalize(_ line: String, keywords: Set<String>, pinning needle: String? = nil) -> Normalized? {
        guard !line.contains(hole) else { return nil }
        let pin = needle?.lowercased()
        var template = "", bindings: [String] = []
        let chars = Array(line)
        var i = 0

        while i < chars.count {
            let c = chars[i]

            if c.isLetter || c == "_" {
                var j = i
                while j < chars.count, chars[j].isLetter || chars[j].isNumber || chars[j] == "_" { j += 1 }
                let ident = String(chars[i..<j])
                let lower = ident.lowercased()
                let isPinned = pin.map { !$0.isEmpty && lower.contains($0) } ?? false
                if keywords.contains(lower) || isPinned {
                    template += ident                    // structure — stays in the block
                } else {
                    template.append(hole); bindings.append(ident)   // a name — becomes a modifier
                }
                i = j
            } else if c.isNumber {
                var j = i
                // Covers 42, 3.14, 0xFF, 1_000, 1e9, 10u8 — one lexical run.
                while j < chars.count, chars[j].isLetter || chars[j].isNumber || chars[j] == "_" || chars[j] == "." { j += 1 }
                template.append(hole); bindings.append(String(chars[i..<j]))
                i = j
            } else if c == "\"" || c == "'" {
                var j = i + 1
                while j < chars.count {
                    if chars[j] == "\\" { j += 2; continue }   // escape: skip the escaped char
                    if chars[j] == c { j += 1; break }         // closing quote
                    j += 1
                }
                let end = min(j, chars.count)
                template.append(hole); bindings.append(String(chars[i..<end]))
                i = end
            } else {
                template.append(c)
                i += 1
            }
        }
        return Normalized(template: template, bindings: bindings)
    }

    /// Fill a template's holes, in order, from `bindings`. Holes beyond the supplied
    /// bindings are left as-is — callers that require exactness must check arity first.
    public static func substitute(template: String, bindings: [String]) -> String {
        var out = ""
        var next = 0
        for ch in template {
            if ch == hole, next < bindings.count {
                out += bindings[next]; next += 1
            } else {
                out.append(ch)
            }
        }
        return out
    }

    /// Exact inverse of `normalize`: substitute the bindings back into the holes, in order.
    public static func denormalize(_ n: Normalized) -> String {
        substitute(template: n.template, bindings: n.bindings)
    }

    /// Human/model-readable rendering of a template: holes shown as `${}`.
    public static func render(_ template: String) -> String {
        String(template.map { $0 == hole ? "◦" : $0 })
            .replacingOccurrences(of: "◦", with: "${}")
    }
}
