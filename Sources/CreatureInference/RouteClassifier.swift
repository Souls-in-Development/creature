// RouteClassifier — the internal "connection oracle" used by gap-fill-and-
// learn routing (see `LearnedRouting.swift` and `resolveRoute` in the CLI).
//
// When the creature meets a prompt category it hasn't routed before, this
// asks Apple's on-device model (FoundationModels) to classify it: a short
// category label plus which soul (conscious/unconscious) should handle it.
// The call is internal only — its raw text is never printed to stdout or
// shown to the user; only the routed reply from the *chosen* soul is.
//
// Structured output uses FoundationModels' guided generation
// (`@Generable`/`@Guide`), verified directly against the SDK's
// swiftinterface (MacOSX26.2 SDK, FoundationModels.swiftmodule,
// arm64e-apple-macos.swiftinterface — Xcode 26.2):
//   - `@Generable` macro: `@attached(extension, ...) @attached(member, ...)
//     public macro Generable(description: String? = nil)` — attach to a
//     struct to make it model-generatable.
//   - `@Guide` macro (peer macro, `T: Generable`): constrains a property.
//     For `String` properties specifically there's an overload taking
//     `GenerationGuide<String>...`, and `GenerationGuide<String>` exposes
//     `static func anyOf(_ values: [String]) -> GenerationGuide<String>` —
//     used here to hard-constrain `role` to exactly the two `PartnerRole`
//     raw values, so the model cannot return anything else.
//   - `LanguageModelSession.respond<Content>(to: String, generating:
//     Content.Type = Content.self, ...) async throws ->
//     Response<Content> where Content: Generable` — the guided-generation
//     overload (confirmed alongside the plain-`String` `respond(to:)` used
//     by `FoundationPartner`).
// If this API shape had been ambiguous or absent, this file would not have
// been written this way — see the task report for the verification trail.

import Foundation
import CreatureSpine
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Structured classification result from the oracle: a coarse category
/// label, which role should own that category, and a short rationale
/// (kept for potential future logging — never shown to the user as-is).
#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
public struct RouteClassification {
    @Guide(description: "A short 1-3 word label for the general topic/kind of this prompt, e.g. 'general knowledge', 'coding', 'creative writing', 'math'.")
    public var category: String

    @Guide(description: "Which soul should handle this prompt.", .anyOf(["conscious", "unconscious"]))
    public var role: String

    @Guide(description: "One short sentence explaining the choice.")
    public var rationale: String
}
#endif

/// Availability-erased result of oracle classification, safe to use from
/// call sites that aren't themselves `@available(macOS 26.0, *)` — mirrors
/// how `makeFoundationPartner` returns `any LLMPartner` rather than the
/// `@available`-gated `FoundationPartner` type directly.
public struct RouteClassificationResult: Sendable {
    public let category: String
    public let role: PartnerRole
    public let rationale: String

    public init(category: String, role: PartnerRole, rationale: String) {
        self.category = category
        self.role = role
        self.rationale = rationale
    }
}

/// Errors specific to oracle-based route classification.
public enum RouteClassifierError: Error, CustomStringConvertible {
    case unavailable
    case classificationFailed(String)
    case invalidRole(String)

    public var description: String {
        switch self {
        case .unavailable: return "Foundation oracle unavailable"
        case .classificationFailed(let msg): return "Route classification failed: \(msg)"
        case .invalidRole(let raw): return "Oracle returned unrecognized role: \(raw)"
        }
    }
}

/// Instructions given to the oracle. Never shown to the user — this session
/// exists purely to fill a routing gap, not to converse.
#if canImport(FoundationModels)
@available(macOS 26.0, *)
private let routeClassifierInstructions = """
Requests are sorted by kind to the soul that handles them. The conscious \
soul handles reasoning, explanation, general knowledge, creative writing, \
and conversation. The unconscious soul handles coding, implementation, \
debugging, and refactoring. Each request is assigned its kind and the soul \
that handles it.
"""

/// Asks Apple's on-device model to classify a prompt into a routing
/// category + role. Returns `nil` if Foundation isn't available on this
/// machine right now (same availability rules as `makeFoundationPartner`).
/// Throws only for a genuine generation failure once Foundation is known
/// to be available.
@available(macOS 26.0, *)
public func classifyRoute(prompt: String) async throws -> RouteClassification? {
    guard case .available = SystemLanguageModel.default.availability else { return nil }

    let session = LanguageModelSession(instructions: routeClassifierInstructions)
    do {
        let response = try await session.respond(
            to: prompt,
            generating: RouteClassification.self
        )
        return response.content
    } catch {
        throw RouteClassifierError.classificationFailed("\(error)")
    }
}
#endif

/// Entry point usable from code that isn't itself `@available`-gated
/// (mirrors the `makeFoundationPartner` seam): returns `nil` when
/// Foundation isn't usable at all (pre-macOS 26, ineligible hardware,
/// Apple Intelligence off, model not ready), or when the oracle failed to
/// classify (never throws — a failed oracle just means "no fill, fall back
/// to heuristic" for the caller).
public func classifyRouteIfAvailable(prompt: String) async -> RouteClassificationResult? {
    #if !canImport(FoundationModels)
    // No on-device oracle here — routing degrades to its heuristic, exactly as
    // it does on Apple hardware without Apple Intelligence.
    return nil
    #else
    guard #available(macOS 26.0, *) else { return nil }
    do {
        guard let classification = try await classifyRoute(prompt: prompt) else { return nil }
        guard let role = PartnerRole(rawValue: classification.role) else { return nil }
        return RouteClassificationResult(
            category: classification.category,
            role: role,
            rationale: classification.rationale
        )
    } catch {
        return nil
    }
    #endif
}
