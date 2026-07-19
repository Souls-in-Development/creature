// Gap-fill-and-learn routing: which slot (conscious/unconscious) should answer.

import Foundation
import CreatureSpine
import CreatureInference

/// The routing heuristic — picks conscious vs unconscious. Deliberately narrow;
/// do not widen it for grounding (`promptWantsCode` is the broader grounding
/// gate).
public func looksLikeCoding(_ prompt: String) -> Bool {
    let codingSignals = ["write", "implement", "code", "function", "class", "refactor", "fix", "bug", "```"]
    return codingSignals.contains { prompt.lowercased().contains($0) }
}

/// Routing debug logging. Off by default; enable with `CREATURE_DEBUG=1` (any
/// non-empty value). Always writes to **stderr** — never stdout, so it never
/// contaminates the creature's actual reply.
let creatureDebugEnabled: Bool = {
    guard let value = ProcessInfo.processInfo.environment["CREATURE_DEBUG"], !value.isEmpty else {
        return false
    }
    return true
}()

public func routeDebugLog(category: String, role: PartnerRole, source: String) {
    guard creatureDebugEnabled else { return }
    let line = "[route: \(category) → \(role.rawValue) (\(source))]\n"
    FileHandle.standardError.write(line.data(using: .utf8)!)
}

/// A cheap, local, deterministic first-guess category for a prompt — used only
/// as the lookup key into `LearnedRouting` before (or instead of) consulting the
/// Foundation oracle. Intentionally coarse: once the oracle has classified a
/// prompt, its (usually more specific) category label is what gets persisted.
public func coarseCategoryGuess(for prompt: String) -> String {
    looksLikeCoding(prompt) ? "coding" : "general"
}

/// Gap-fill-and-learn routing: the creature learns each routing decision so the
/// Foundation oracle is consulted only once per category, ever.
///
///   1. HIT  — category already in `LearnedRouting` -> return the stored role.
///   2. GAP  — category unseen and Foundation is available -> ask Foundation to
///      classify (structured output, internal-only, never printed), learn the
///      result, persist it, return the role.
///   3. DEGRADE — Foundation unavailable (or the oracle call itself fails) ->
///      fall back to the `looksLikeCoding` heuristic. No oracle, no learning,
///      but the creature still routes.
///
/// `CREATURE_DEBUG=1` logs each decision to stderr for demonstration; the
/// user-facing output is never affected by this function's internals.
public func resolveRoute(for prompt: String) async -> PartnerRole {
    var routing = LearnedRouting.load()

    let lookupKey = coarseCategoryGuess(for: prompt)
    if let hit = routing.decision(for: lookupKey) {
        routeDebugLog(category: lookupKey, role: hit.role, source: "learned")
        return hit.role
    }

    if let classification = await classifyRouteIfAvailable(prompt: prompt) {
        let decision = RouteDecision(role: classification.role, confidence: 0.75)
        routing.learn(category: classification.category, decision: decision)
        // Also learn under the coarse lookup key so the next prompt with the
        // same cheap first-guess is a HIT without needing the oracle's exact
        // category label to match the heuristic's guess.
        routing.learn(category: lookupKey, decision: decision)
        try? routing.save()
        routeDebugLog(category: classification.category, role: classification.role, source: "oracle")
        return classification.role
    }

    // Degrade: no oracle available, no learning — heuristic keeps the creature
    // routing.
    let fallbackRole: PartnerRole = looksLikeCoding(prompt) ? .unconscious : .conscious
    routeDebugLog(category: lookupKey, role: fallbackRole, source: "heuristic")
    return fallbackRole
}
