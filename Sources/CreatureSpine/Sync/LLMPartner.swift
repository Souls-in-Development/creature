import Foundation

/// Metadata for an LLM partner in the terminal coding platform.
public struct PartnerMetadata: Sendable, Codable {
    /// Display name (e.g., "Claude 4", "Qwen 3.5 Coder")
    public let name: String

    /// Provider identifier
    public let provider: String

    /// Role this partner is calibrated for
    public let preferredRole: PartnerRole

    /// Estimated latency in milliseconds
    public let latencyMs: Double

    public init(name: String, provider: String, preferredRole: PartnerRole, latencyMs: Double) {
        self.name = name
        self.provider = provider
        self.preferredRole = preferredRole
        self.latencyMs = latencyMs
    }
}

/// The two roles in the terminal coding pair.
public enum PartnerRole: String, Sendable, Codable {
    /// Reasoning, architecture, explanation — the "conscious" mind
    case conscious

    /// Implementation, code generation, refactoring — the "unconscious" muscle
    case unconscious
}

/// Protocol for any LLM that can be plugged into the terminal.
/// Strings in, strings out. No vendor-specific types.
public protocol LLMPartner: Sendable {
    var metadata: PartnerMetadata { get }

    /// Complete a prompt. Returns the response string.
    func complete(prompt: String, system: String?) async throws -> String
}

/// Characteristics extracted from a single response.
public struct ResponseFingerprint: Sendable {
    /// Raw response content
    public let content: String

    /// Total latency for this response
    public let latencyMs: Double

    /// Does the response contain code blocks?
    public let hasCodeBlocks: Bool

    /// Does the response contain explanatory prose?
    public let hasExplanation: Bool

    /// Structural density (0-1): lists, headers, tables
    public let structureDensity: Float

    /// Response length in characters
    public let length: Int

    public init(content: String, latencyMs: Double) {
        self.content = content
        self.latencyMs = latencyMs
        self.length = content.count

        // Simple analysis
        self.hasCodeBlocks = content.contains("```")
        self.hasExplanation = content.contains("because") || content.contains("therefore") ||
                              content.contains("however") || content.contains("this means")

        // Count structural elements
        let lines = content.components(separatedBy: .newlines)
        var structuralLines = 0
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") || trimmed.hasPrefix("-") ||
               trimmed.hasPrefix("|") || trimmed.hasPrefix("1.") {
                structuralLines += 1
            }
        }
        self.structureDensity = Float(structuralLines) / max(Float(lines.count), 1)
    }
}
