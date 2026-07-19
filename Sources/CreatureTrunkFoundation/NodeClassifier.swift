// NodeClassifier — Foundation-assist for the tentacles.
//
// The syntactic tentacles (CreatureTrunkSwift, CreatureTrunkPython) can tell
// you a node's *structure* (it's a `func`, arity 2, nested under `Foo`) but
// not its *meaning* (is this networking code? persistence? crypto?). That
// semantic dimension is exactly what Apple's on-device model is good at and
// what a syntax tree cannot derive — so this generalises `RouteClassifier`
// (CreatureInference/RouteClassifier.swift, "which soul handles this prompt")
// to "what kind of code is this node" (see
// `docs/plans/2026-07-05-creature-cursor-competitor-architecture.md` §Build
// log "Next" #1 and §2, "Foundation = internal machine-side oracle").
//
// Deliberately lives in its own target (`CreatureTrunkFoundation`) depending
// on `CreatureTrunk` only — no `CreatureInference`, no MLX. It imports the
// system `FoundationModels` framework directly, exactly like
// `CreatureInference/RouteClassifier.swift` and `FoundationPartner.swift` do,
// so the same `@available(macOS 26.0, *)` gating pattern applies here.
//
// Structured output uses FoundationModels' guided generation
// (`@Generable`/`@Guide`), verified directly against the SDK's
// swiftinterface (MacOSX26.2 SDK, FoundationModels.swiftmodule,
// arm64e-apple-macos.swiftinterface — Xcode 26.2), the same API surface
// `RouteClassifier` already verified and uses:
//   - `@Generable` macro: `@attached(extension, ...) @attached(member, ...)
//     public macro Generable(description: String? = nil)` — attach to a
//     struct to make it model-generatable.
//   - `@Guide` macro (peer macro, `T: Generable`): constrains a property.
//     For `String` properties there's an overload taking
//     `GenerationGuide<String>...`, and `GenerationGuide<String>` exposes
//     `static func anyOf(_ values: [String]) -> GenerationGuide<String>` —
//     used here to hard-constrain `domain` to a fixed vocabulary, so the
//     model structurally cannot return anything outside it.
//   - `LanguageModelSession.respond<Content>(to: String, generating:
//     Content.Type = Content.self, ...) async throws ->
//     Response<Content> where Content: Generable` — the guided-generation
//     overload.
// This file does not guess at the API shape; it reuses the exact surface
// `RouteClassifier` already confirmed against the resolved SDK.

import Foundation
import CreatureTrunk
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The fixed vocabulary of code domains Foundation is allowed to choose from.
/// Kept small and stable so the learned cache (`LearnedNodeClassifications`)
/// stays meaningful across runs — a growing/unstable vocabulary would defeat
/// the point of caching by `truthKey`.
public enum CodeDomain {
    public static let all: [String] = [
        "networking",
        "persistence",
        "ui",
        "math",
        "crypto",
        "parsing",
        "concurrency",
        "testing",
        "logging",
        "general"
    ]
}

/// Structured classification result from the oracle: a coarse domain label
/// (constrained to `CodeDomain.all`) plus a one-line summary of what the node
/// does. Mirrors `RouteClassification`'s shape in CreatureInference.
#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
public struct NodeClassification {
    @Guide(description: "The domain/purpose this code node belongs to.", .anyOf(CodeDomain.all))
    public var domain: String

    @Guide(description: "One short sentence summarizing what this node does.")
    public var summary: String
}
#endif

/// Availability-erased result of oracle classification, safe to use from call
/// sites that aren't themselves `@available(macOS 26.0, *)` — mirrors
/// `RouteClassificationResult`. This is also the `Codable` shape persisted by
/// `LearnedNodeClassifications`, so a cache hit and a fresh oracle call are
/// indistinguishable to callers.
public struct NodeClassificationResult: Sendable, Codable, Equatable {
    public let domain: String
    public let summary: String

    public init(domain: String, summary: String) {
        self.domain = domain
        self.summary = summary
    }
}

/// Errors specific to oracle-based node classification.
public enum NodeClassifierError: Error, CustomStringConvertible {
    case unavailable
    case classificationFailed(String)

    public var description: String {
        switch self {
        case .unavailable: return "Foundation oracle unavailable"
        case .classificationFailed(let msg): return "Node classification failed: \(msg)"
        }
    }
}

/// Instructions given to the oracle. Never shown to the user — this session
/// exists purely to sort a code node into a domain, not to converse. No
/// persona, no "do not" — the model only ever fills the guided schema, so it
/// structurally cannot free-form an answer regardless of instruction wording.
#if canImport(FoundationModels)
@available(macOS 26.0, *)
private let nodeClassifierInstructions = """
Code nodes are sorted by domain and summarized. Each node is a declaration \
(function, type, or property) shown as its normalized structural skeleton \
plus its source text. The domain is the area of programming concern the \
node's source text belongs to, and the summary is one short sentence \
describing what the node does.
"""

/// Asks Apple's on-device model to classify one code node's skeleton +
/// source into a domain + summary. Returns `nil` if Foundation isn't
/// available on this machine right now (same availability rules as
/// `makeFoundationPartner`/`classifyRoute`). Throws only for a genuine
/// generation failure once Foundation is known to be available.
@available(macOS 26.0, *)
public func classifyNode(skeleton: String, source: String) async throws -> NodeClassification? {
    guard case .available = SystemLanguageModel.default.availability else { return nil }

    let session = LanguageModelSession(instructions: nodeClassifierInstructions)
    let prompt = """
    Skeleton: \(skeleton)
    Source:
    \(source)
    """
    do {
        let response = try await session.respond(
            to: prompt,
            generating: NodeClassification.self
        )
        return response.content
    } catch {
        throw NodeClassifierError.classificationFailed("\(error)")
    }
}
#endif

/// Entry point usable from code that isn't itself `@available`-gated (mirrors
/// `classifyRouteIfAvailable`): returns `nil` when Foundation isn't usable at
/// all (pre-macOS 26, ineligible hardware, Apple Intelligence off, model not
/// ready), or when the oracle failed to classify (never throws — a failed
/// oracle just means "no fill, leave this node unclassified" for the caller).
public func classifyIfAvailable(skeleton: String, source: String) async -> NodeClassificationResult? {
    #if !canImport(FoundationModels)
    // No on-device oracle on this platform — callers degrade to their heuristic,
    // exactly as they do on Apple hardware without Apple Intelligence.
    return nil
    #else
    guard #available(macOS 26.0, *) else { return nil }
    do {
        guard let classification = try await classifyNode(skeleton: skeleton, source: source) else { return nil }
        return NodeClassificationResult(domain: classification.domain, summary: classification.summary)
    } catch {
        return nil
    }
    #endif
}
