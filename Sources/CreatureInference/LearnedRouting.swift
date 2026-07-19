// LearnedRouting — the gap-fill-and-learn connections store.
//
// Foundation (Apple's on-device model) acts as an internal, never-user-facing
// "connection oracle": the FIRST time the creature meets a prompt category it
// hasn't routed before, it asks Foundation to classify the category and pick
// a role (conscious/unconscious). That decision is written here, keyed by
// category, so every subsequent prompt in the same category is routed
// instantly from disk — no Foundation call, no oracle, just a learned fact.
//
// This is deliberately a separate store from `SyncProfile` (which calibrates
// partner *weights* within a role) — connections here are routing *category
// -> role* facts, a different axis, and keeping them separate avoids churn
// in the calibration format.

import Foundation
import CreatureSpine

/// A single learned routing decision: which role handles a given prompt
/// category, and how confident the oracle (or heuristic) was when it made
/// the call.
public struct RouteDecision: Sendable, Codable, Equatable {
    public let role: PartnerRole
    public let confidence: Double

    public init(role: PartnerRole, confidence: Double) {
        self.role = role
        self.confidence = confidence
    }
}

/// Persisted map of prompt category -> learned routing decision.
/// Lives at `~/.creature/connections.json`, independent of `SyncProfile`.
public struct LearnedRouting: Sendable, Codable {
    public var connections: [String: RouteDecision]

    public static let defaultPath = "\(NSHomeDirectory())/.creature/connections.json"

    public init(connections: [String: RouteDecision] = [:]) {
        self.connections = connections
    }

    /// Look up a previously learned decision for a category. Categories are
    /// matched case-insensitively so "General Knowledge" and "general
    /// knowledge" hit the same entry.
    public func decision(for category: String) -> RouteDecision? {
        connections[Self.normalize(category)]
    }

    /// Record (or overwrite) a decision for a category.
    public mutating func learn(category: String, decision: RouteDecision) {
        connections[Self.normalize(category)] = decision
    }

    public static func normalize(_ category: String) -> String {
        category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Load from disk. Returns an empty store if the file doesn't exist yet
    /// or fails to decode — a fresh/missing connections file is not an error,
    /// it just means nothing has been learned yet.
    public static func load(from path: String = LearnedRouting.defaultPath) -> LearnedRouting {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return LearnedRouting()
        }
        guard let decoded = try? JSONDecoder().decode(LearnedRouting.self, from: data) else {
            return LearnedRouting()
        }
        return decoded
    }

    /// Persist to disk, creating `~/.creature/` if needed.
    public func save(to path: String = LearnedRouting.defaultPath) throws {
        let dir = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: URL(fileURLWithPath: path))
    }
}
