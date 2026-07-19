// FoundationAvailability — availability reporting for the node classifier.
//
// Duplicates the small `FoundationAvailabilityReason` shape from
// `CreatureInference/FoundationPartner.swift` rather than depending on that
// target: `CreatureTrunkFoundation` is deliberately MLX-free and
// `CreatureInference`-free (see `Package.swift`'s doc comment on this
// target), so it needs its own copy of this seam to report *why* Foundation
// isn't usable, without pulling in the inference stack just for a availability
// enum. The values and meaning are identical to `FoundationPartner`'s.

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Why `classifyIfAvailable` (or the CLI's `classify` command) can't reach
/// Foundation right now. Mirrors `SystemLanguageModel.Availability.UnavailableReason`
/// (macOS 26+) plus a pre-26 case, so callers on any deployment target can
/// print a helpful message without themselves needing `@available`.
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

/// Reports *why* the on-device model isn't usable right now, so the CLI can
/// print a helpful message instead of a bare "unavailable". Returns `nil`
/// when the model **is** available.
public func foundationUnavailableReason() -> FoundationAvailabilityReason? {
    #if !canImport(FoundationModels)
    // No FoundationModels framework on this platform at all.
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
