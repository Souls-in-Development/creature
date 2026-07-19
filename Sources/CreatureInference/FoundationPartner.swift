// FoundationPartner — runs Apple's on-device model via the FoundationModels
// framework (Apple Intelligence). This is the "teacher" runtime for Stage C:
// no download, no server, the model Apple already ships with the OS.
//
// FoundationModels is a macOS/iOS 26+ system framework — no new SwiftPM
// dependency. Everything that touches it is gated with `@available(macOS
// 26.0, *)` so the package keeps compiling (and running, for non-FoundationPartner
// code paths) down to the package's macOS 14 deployment target.
//
// API surface verified directly against the SDK's swiftinterface
// (MacOSX26.2.sdk/.../FoundationModels.swiftmodule/arm64e-apple-macos.swiftinterface),
// not guessed:
//   - `SystemLanguageModel.default` / `.availability` -> `SystemLanguageModel.Availability`
//     which is `.available` or `.unavailable(UnavailableReason)`, and
//     `UnavailableReason` is exactly `.deviceNotEligible` / `.appleIntelligenceNotEnabled`
//     / `.modelNotReady`.
//   - `LanguageModelSession(instructions:)` — the `Swift.String?` overload
//     (`convenience public init(model:tools:instructions: Swift.String? = nil)`).
//   - `session.respond(to: String) async throws -> LanguageModelSession.Response<String>`,
//     and `Response<Content>.content: Content` — so `.content` is the `String` reply.

import Foundation
import CreatureSpine
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Errors specific to on-device FoundationModels inference.
public enum FoundationPartnerError: Error, CustomStringConvertible {
    case unavailable(String)
    case generationFailed(String)

    public var description: String {
        switch self {
        case .unavailable(let msg): return "Apple Intelligence unavailable: \(msg)"
        case .generationFailed(let msg): return "FoundationModels generation failed: \(msg)"
        }
    }
}

/// Why `makeFoundationPartner` returned `nil`. Mirrors
/// `SystemLanguageModel.Availability.UnavailableReason` (macOS 26+) plus a
/// pre-26 case, so callers on any deployment target can print a helpful
/// message without themselves needing `@available`.
public enum FoundationAvailabilityReason: Sendable, CustomStringConvertible {
    /// Running on an OS older than macOS 26 — FoundationModels doesn't exist here.
    case osTooOld
    /// Hardware isn't eligible for Apple Intelligence.
    case deviceNotEligible
    /// Apple Intelligence exists on this hardware but isn't turned on.
    case appleIntelligenceNotEnabled
    /// Eligible + enabled, but the on-device model assets aren't ready yet.
    case modelNotReady
    /// Not an Apple platform — FoundationModels does not exist here at all.
    case unsupportedPlatform

    public var description: String {
        switch self {
        case .osTooOld:
            return "needs macOS 26 + eligible hardware"
        case .deviceNotEligible:
            return "this device is not eligible for Apple Intelligence"
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence not enabled — enable it in Settings, or needs macOS 26 + eligible hardware"
        case .modelNotReady:
            return "the on-device model isn't ready yet — it may still be downloading"
        case .unsupportedPlatform:
            return "Apple Intelligence is only available on Apple platforms"
        }
    }
}

/// An `LLMPartner` backed by Apple's on-device system model
/// (FoundationModels / Apple Intelligence). No download, no server — the
/// model ships with the OS. macOS 26+ only; construct via
/// `makeFoundationPartner(role:)` rather than the initializer directly so
/// availability is always checked first.
#if canImport(FoundationModels)
@available(macOS 26.0, *)
public struct FoundationPartner: LLMPartner {
    public let metadata: PartnerMetadata

    /// Default instructions used when no `system` prompt is supplied to `complete`.
    public static let defaultInstructions = """
    You are the creature — a living terminal running entirely on-device via \
    Apple Intelligence. Be concise and direct. When asked for code, return \
    only the code unless an explanation is explicitly requested.
    """

    public init(preferredRole: PartnerRole) {
        self.metadata = PartnerMetadata(
            name: "Apple Intelligence (on-device)",
            provider: "FoundationModels (in-process)",
            preferredRole: preferredRole,
            latencyMs: 0
        )
    }

    public func complete(prompt: String, system: String?) async throws -> String {
        let session = LanguageModelSession(instructions: system ?? Self.defaultInstructions)

        do {
            let response = try await session.respond(to: prompt)
            return response.content
        } catch {
            throw FoundationPartnerError.generationFailed("\(error)")
        }
    }
}
#endif

/// Factory: builds a `FoundationPartner` when (and only when) the on-device
/// model is actually usable on this machine right now. Returns `nil`
/// otherwise — pre-macOS-26 deployments, ineligible hardware, Apple
/// Intelligence turned off, or model assets not yet ready.
///
/// This is the availability seam: `LLMPartner` itself carries no
/// `@available` annotation, so callers built for a macOS 14 deployment
/// target can call this factory unconditionally and get back either a
/// working partner or `nil` — never a compile-time or runtime trap.
public func makeFoundationPartner(role: PartnerRole) -> (any LLMPartner)? {
    #if !canImport(FoundationModels)
    return nil
    #else
    guard #available(macOS 26.0, *) else { return nil }
    guard case .available = SystemLanguageModel.default.availability else { return nil }
    return FoundationPartner(preferredRole: role)
    #endif
}

/// Companion to `makeFoundationPartner(role:)`: reports *why* the on-device
/// model isn't usable right now, so the CLI can print a helpful message
/// instead of a bare "unavailable". Returns `nil` when the model **is**
/// available (i.e. `makeFoundationPartner` would have succeeded).
public func foundationUnavailableReason() -> FoundationAvailabilityReason? {
    #if !canImport(FoundationModels)
    return .unsupportedPlatform
    #else
    guard #available(macOS 26.0, *) else { return .osTooOld }

    switch SystemLanguageModel.default.availability {
    case .available:
        return nil
    case .unavailable(let reason):
        switch reason {
        case .deviceNotEligible: return .deviceNotEligible
        case .appleIntelligenceNotEnabled: return .appleIntelligenceNotEnabled
        case .modelNotReady: return .modelNotReady
        @unknown default: return .appleIntelligenceNotEnabled
        }
    }
    #endif
}
