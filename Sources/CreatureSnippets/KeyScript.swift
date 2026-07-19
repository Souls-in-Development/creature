import Foundation

/// The unconscious's voice: a citation into the reference system rather than free tokens.
///
/// Two primitives, plus an escape hatch:
///
///     ^abc             cite  — emit the stored line for key "abc", verbatim
///     ^abc | os | d    bind  — emit key "abc"'s block, filling its holes in order
///     + let x = 1      gen   — emit literal text (novel code that has no key yet)
///
/// A cited key can never be ambiguous: `SnippetStore` is content-addressed, so `key →
/// content` is a bijection. That is the whole reason a terse register is safe here and is
/// not safe in, say, medical shorthand. Do not introduce a resolution path that lets one
/// key map to two contents.
///
/// Foundation only. No parser, no grammar, no model.
public enum KeyScript {
    public enum Instruction: Sendable, Equatable {
        case cite(key: String)
        case bind(key: String, bindings: [String])
        case gen(text: String)
    }

    public enum Failure: Error, Sendable, Equatable {
        /// The script cited a key the store does not hold. The bijection guard.
        case unknownKey(String)
        /// Bindings supplied ≠ holes in the block. A partial fill would emit a NUL.
        case arityMismatch(key: String, expected: Int, got: Int)
        /// The stored line could not be α-normalized (it already contains the hole marker).
        case notNormalizable(key: String)
    }

    /// `nil` when any line fails to parse — a key script is all-or-nothing, so a prose
    /// response can never be silently half-interpreted as citations.
    public static func parse(_ text: String) -> [Instruction]? {
        var out: [Instruction] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("+") {
                var text = String(line.dropFirst())
                if text.hasPrefix(" ") { text.removeFirst() }
                out.append(.gen(text: text))
                continue
            }

            guard line.hasPrefix("^") else { return nil }
            let body = line.dropFirst()
            let parts = body.split(separator: "|", omittingEmptySubsequences: false)
            guard let head = parts.first else { return nil }

            let key = head.trimmingCharacters(in: .whitespaces)
            guard isValidKey(key) else { return nil }

            if parts.count == 1 {
                out.append(.cite(key: key))
            } else {
                var bindings: [String] = []
                for p in parts.dropFirst() {
                    let b = p.trimmingCharacters(in: .whitespaces)
                    guard !b.isEmpty else { return nil }
                    bindings.append(b)
                }
                out.append(.bind(key: key, bindings: bindings))
            }
        }
        return out
    }

    /// The LetterKey alphabet: lowercase a–z, non-empty.
    static func isValidKey(_ key: String) -> Bool {
        !key.isEmpty && key.allSatisfy { $0.isLowercase && $0.isLetter && $0.isASCII }
    }

    /// True when `text` parses AND actually cites the library. A script of pure `gen`
    /// lines is just text wearing a `+`; it is not the key basis.
    public static func isKeyScript(_ text: String) -> Bool {
        guard let instructions = parse(text), !instructions.isEmpty else { return false }
        return instructions.contains { if case .gen = $0 { return false } else { return true } }
    }

    /// Resolve a script into source text. Every cited key must exist in `store`; every
    /// `bind` must supply exactly as many bindings as the block has holes. Nothing is
    /// guessed and nothing is generated: the only novel text is whatever `gen` carried.
    ///
    /// Line discipline: stored lines keep their trailing newline. An emitted chunk that
    /// lacks one gets one, so instructions stay line-separated.
    public static func resolve(
        _ instructions: [Instruction],
        store: SnippetStore,
        keywords: Set<String>
    ) throws -> String {
        var out = ""

        func emit(_ chunk: String) {
            out += chunk
            if !chunk.hasSuffix("\n") { out += "\n" }
        }

        for instruction in instructions {
            switch instruction {
            case .gen(let text):
                emit(text)

            case .cite(let key):
                guard let line = store.line(forKey: key) else { throw Failure.unknownKey(key) }
                emit(line)

            case .bind(let key, let bindings):
                guard let line = store.line(forKey: key) else { throw Failure.unknownKey(key) }
                guard let n = SnippetNormalizer.normalize(line, keywords: keywords) else {
                    throw Failure.notNormalizable(key: key)
                }
                guard n.holeCount == bindings.count else {
                    throw Failure.arityMismatch(key: key, expected: n.holeCount, got: bindings.count)
                }
                emit(SnippetNormalizer.substitute(template: n.template, bindings: bindings))
            }
        }
        return out
    }
}
