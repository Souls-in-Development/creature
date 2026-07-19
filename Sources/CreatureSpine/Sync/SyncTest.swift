import Foundation
// On Linux/Windows, Foundation's networking lives in a separate module.
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A single sync test to probe how the pair works together.
public struct SyncTest: Sendable {
    public let id: String
    public let name: String
    public let prompt: String
    public let systemPrompt: String?
    public let expectedRole: PartnerRole
    public let weight: Float

    public init(id: String, name: String, prompt: String,
                systemPrompt: String? = nil, expectedRole: PartnerRole, weight: Float = 1.0) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.systemPrompt = systemPrompt
        self.expectedRole = expectedRole
        self.weight = weight
    }
}

/// Standard sync test suite for terminal coding pairs.
public struct StandardSyncTests {

    public static let all: [SyncTest] = reasoningTests + codingTests + hybridTests

    /// Tests that should favor the conscious (reasoning) partner.
    public static let reasoningTests: [SyncTest] = [
        SyncTest(
            id: "r1",
            name: "Architecture Decision",
            prompt: "We're building a real-time chat system. Should we use WebSockets or Server-Sent Events? Consider reliability, scalability, and fallback strategies.",
            expectedRole: .conscious,
            weight: 1.2
        ),

        SyncTest(
            id: "r2",
            name: "Trade-off Analysis",
            prompt: "Compare strong typing vs dynamic typing for a startup's MVP. What are the long-term implications of each choice?",
            expectedRole: .conscious,
            weight: 1.0
        ),

        SyncTest(
            id: "r3",
            name: "Debugging Strategy",
            prompt: "A production service has intermittent 500 errors that don't appear in logs. Outline a systematic debugging approach.",
            expectedRole: .conscious,
            weight: 1.1
        ),
    ]

    /// Tests that should favor the unconscious (coding) partner.
    public static let codingTests: [SyncTest] = [
        SyncTest(
            id: "c1",
            name: "Implement Function",
            prompt: "Write a Swift function that validates an email address using regex. Include error handling.",
            systemPrompt: "Respond with only the code, no explanation.",
            expectedRole: .unconscious,
            weight: 1.2
        ),

        SyncTest(
            id: "c2",
            name: "Refactor Code",
            prompt: "Refactor this to use async/await: \"func fetchData(completion: @escaping (Result<Data, Error>) -> Void) { URLSession.shared.dataTask(...) }\"",
            systemPrompt: "Provide only the refactored code.",
            expectedRole: .unconscious,
            weight: 1.1
        ),

        SyncTest(
            id: "c3",
            name: "Generate Schema",
            prompt: "Create a PostgreSQL schema for a blog with users, posts, tags, and comments. Include indexes.",
            expectedRole: .unconscious,
            weight: 1.0
        ),
    ]

    /// Tests that require both partners.
    public static let hybridTests: [SyncTest] = [
        SyncTest(
            id: "h1",
            name: "Design and Implement",
            prompt: "Design a rate limiter for an API, then implement the core algorithm in Python.",
            expectedRole: .conscious, // Conscious leads, unconscious follows
            weight: 1.3
        ),

        SyncTest(
            id: "h2",
            name: "Explain and Fix",
            prompt: "This code has a race condition. Explain why it happens and provide the fixed version. \"var counter = 0; DispatchQueue.concurrentPerform(iterations: 1000) { counter += 1 }\"",
            expectedRole: .conscious,
            weight: 1.2
        ),

        SyncTest(
            id: "h3",
            name: "Review Code",
            prompt: "Review this function for security issues: \"func login(username: String, password: String) -> Bool { return query(\"SELECT * FROM users WHERE user='\\(username)' AND pass='\\(password)'\") != nil }\"",
            expectedRole: .conscious,
            weight: 1.1
        ),
    ]
}
