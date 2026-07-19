import Foundation

/// Groups the store's exact lines into **Type-2 clone classes**: distinct lines that are
/// the same block once identifiers and literals are abstracted to holes.
///
/// This is the layer that sees "still a virtual environment, different name, different
/// path." `SnippetStore` is content-addressed and therefore Type-1 only — `venv_a` and
/// `venv_b` are two unrelated keys to it. A clone class puts them back together, and its
/// template is the same kind of object as the bundled construct snippets in
/// `snippets.json`, so harvested real code and authored constructs finally share a shape.
///
/// Built as an index *over* the store — the lossless on-disk format is untouched.
public struct TemplateIndex: Sendable {
    public struct CloneClass: Sendable {
        /// The block, holes and all (render with `SnippetNormalizer.render`).
        public let template: String
        /// The distinct exact-line keys that collapse onto this template.
        public let lineKeys: [String]
        /// A few of the original lines, for showing the variation.
        public let examples: [String]
        /// How many distinct concrete lines are the same block.
        public var variants: Int { lineKeys.count }
        /// Holes in the template — the variables and modifiers the document supplies.
        public var holeCount: Int { template.filter { $0 == SnippetNormalizer.hole }.count }
    }

    /// Prose lines (comments) normalize to near-empty templates full of holes and would
    /// collide en masse, so they're excluded. A line qualifies as code when it carries at
    /// least one structural character and doesn't open with a comment marker.
    static func looksLikeCode(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        for marker in ["//", "#", "*", "--", ";;", "\"\"\"", "'''", "/*"] where t.hasPrefix(marker) {
            return false
        }
        return t.contains(where: { "(){}[]=;:".contains($0) })
    }

    /// Literal (non-hole, non-whitespace) characters left in a template — how much of the
    /// line is **block** rather than **modifier**. Only keywords survive normalization as
    /// letters, so this counts keywords and structural punctuation together.
    ///
    ///     ${} = ${}          → 1   nearly all the information is in the bindings
    ///     ${}: ${},          → 2   a dict entry; a shape, not a construct
    ///     ${} = ${}(${})     → 3   a CALL — still a virtual environment
    ///     self.${} = ${}     → 6
    ///     def ${}(self):     → 10
    ///
    /// A threshold of 3 is what separates "same block, different names" from "two things
    /// either side of an equals sign".
    static func structuralMass(_ template: String) -> Int {
        template.reduce(0) { $0 + (($1 == SnippetNormalizer.hole || $1.isWhitespace) ? 0 : 1) }
    }

    /// Group every interned line by its normalized template. Only classes with at least
    /// `minVariants` distinct lines are returned — those are the ones the exact store
    /// could not see. Sorted by variant count, descending.
    ///
    /// `minStructuralMass` drops shapes that carry no block (see `structuralMass`), which
    /// otherwise dominate the ranking by sheer count while saying nothing. Pass 0 to group
    /// every Type-2 class regardless.
    public static func cloneClasses(
        in store: SnippetStore,
        keywords: Set<String>,
        minVariants: Int = 2,
        top: Int = 20,
        minStructuralMass: Int = 3
    ) -> [CloneClass] {
        var byTemplate: [String: [String]] = [:]   // template -> line keys

        for key in store.allLineKeys {
            guard let line = store.line(forKey: key), looksLikeCode(line) else { continue }
            guard let n = SnippetNormalizer.normalize(line, keywords: keywords), n.holeCount > 0 else { continue }
            guard structuralMass(n.template) >= minStructuralMass else { continue }
            byTemplate[n.template, default: []].append(key)
        }

        return byTemplate
            .filter { $0.value.count >= minVariants }
            .sorted { ($0.value.count, $0.key) > ($1.value.count, $1.key) }
            .prefix(top)
            .map { template, keys in
                CloneClass(
                    template: template,
                    lineKeys: keys,
                    examples: keys.prefix(3).compactMap { store.line(forKey: $0)?.trimmingCharacters(in: .whitespacesAndNewlines) }
                )
            }
    }
}
