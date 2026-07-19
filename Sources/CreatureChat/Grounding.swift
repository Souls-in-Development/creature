// Snippet grounding: the seam that lets EVERY plugged-in model answer from a
// verified real-code corpus instead of inventing syntax — same grounding for
// the remote, embedded-MLX, and Apple-Foundation partners alike.

import Foundation
import CreatureSnippets

/// Process-wide access to the snippet library. Loads the harvested real-code
/// corpus from `$CREATURE_LIBRARY` (or ~/.creature/library.snip) if present —
/// else the bundled canonical constructs only — exactly once, on first use
/// (Swift global-let semantics), so non-model paths pay nothing. Public because
/// the CLI's `ground`/`cite` diagnostics inspect the same shared instance.
public let snippetRetriever: SnippetRetriever = {
    let path = ProcessInfo.processInfo.environment["CREATURE_LIBRARY"]
        ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".creature/library.snip").path
    return SnippetRetriever(store: try? SnippetStore.load(from: URL(fileURLWithPath: path)))
}()

/// Best-effort language detection from a prompt, so grounding is scoped (never a
/// noisy all-languages dump). Returns nil when no language is named — grounding
/// then stays out of the way.
public func groundingLanguage(in prompt: String) -> String? {
    let aliases = ["js": "javascript", "ts": "typescript", "py": "python", "c++": "cpp",
                   "cplusplus": "cpp", "c#": "csharp", "golang": "go", "objective-c": "objc",
                   "obj-c": "objc", "rustlang": "rust", "nodejs": "javascript"]
    let tokens = prompt.lowercased().split { !($0.isLetter || $0.isNumber || $0 == "+" || $0 == "#") }.map(String.init)
    for t in tokens {
        if let a = aliases[t] { return a }
        if snippetRetriever.languages.byName[t] != nil { return t }
    }
    return nil
}

/// Grounding's own gate, deliberately broader than `looksLikeCoding` — which is
/// the ROUTING heuristic (it picks conscious vs unconscious) and must not be
/// widened here. Asking how to *call* or *use* a symbol is a code question even
/// though it trips none of the routing signals. Pairs with `groundingLanguage`:
/// both must hold, so an ordinary sentence that happens to contain a language
/// word never drags in snippets.
public func promptWantsCode(_ prompt: String) -> Bool {
    if looksLikeCoding(prompt) { return true }
    let intent: Set<String> = ["call", "use", "using", "syntax", "example", "method",
                               "loop", "import", "print", "struct", "enum", "api",
                               "snippet", "declare", "define", "return", "compile",
                               "error", "exception", "script", "program", "iterate"]
    let tokens = prompt.lowercased().split { !($0.isLetter || $0.isNumber) }.map(String.init)
    return tokens.contains { intent.contains($0) }
}

/// The grounded snippet block for a prompt, or "" when it shouldn't apply (not a
/// code prompt, or no language named). Safe to prepend unconditionally.
public func snippetGrounding(for prompt: String) -> String {
    guard promptWantsCode(prompt), let lang = groundingLanguage(in: prompt) else { return "" }
    return snippetRetriever.contextBlock(for: prompt, language: lang)
}

/// Fold snippet grounding into whatever system prompt a call already had — the
/// verified syntax goes first (the model reads ground-truth before anything
/// else), then the base. Returns nil only when there is neither, so it drops
/// into every `system:` argument.
public func groundedSystem(_ base: String?, prompt: String) -> String? {
    let block = snippetGrounding(for: prompt)
    if block.isEmpty { return base }
    guard let base, !base.isEmpty else { return block }
    return block + "\n\n" + base
}
