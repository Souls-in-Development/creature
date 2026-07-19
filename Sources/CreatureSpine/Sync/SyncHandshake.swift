import Foundation

/// Errors during sync calibration.
public enum SyncError: Error, Sendable {
    case partnerTimeout(PartnerRole)
    case partnerFailed(PartnerRole, String)
    case insufficientData(String)
    case calibrationFailed(String)
}

/// Result of a sync handshake.
public enum SyncResult: Sendable {
    case success(SyncProfile)
    case partial(SyncProfile, [SyncError])
    case failure(SyncError)
}

/// Calibrates two LLM partners for synchronized teamwork.
///
/// The handshake runs a series of tests to determine:
/// 1. Which partner is better at reasoning (conscious)
/// 2. Which partner is better at coding (unconscious)
/// 3. How to route tasks between them for optimal collaboration
///
/// The LLMs don't need to know they're conscious/unconscious.
/// They just need to do the right thing.
public actor SyncHandshake {
    private let partnerA: any LLMPartner
    private let partnerB: any LLMPartner
    private let tests: [SyncTest]
    private let timeoutSeconds: UInt64

    public init(
        partnerA: any LLMPartner,
        partnerB: any LLMPartner,
        tests: [SyncTest] = StandardSyncTests.all,
        timeoutSeconds: UInt64 = 60
    ) {
        self.partnerA = partnerA
        self.partnerB = partnerB
        self.tests = tests
        self.timeoutSeconds = timeoutSeconds
    }

    /// Execute the sync handshake.
    public func calibrate() async -> SyncResult {
        var resultsA: [TestResult] = []
        var resultsB: [TestResult] = []
        var errors: [SyncError] = []

        // Run all tests against both partners
        for test in tests {
            async let resultATask = runTest(test, partner: partnerA, role: .conscious)
            async let resultBTask = runTest(test, partner: partnerB, role: .unconscious)

            let (resultA, resultB) = await (resultATask, resultBTask)

            if let ra = resultA {
                resultsA.append(ra)
            } else {
                errors.append(.partnerTimeout(.conscious))
            }

            if let rb = resultB {
                resultsB.append(rb)
            } else {
                errors.append(.partnerTimeout(.unconscious))
            }
        }

        // Need at least half the tests to succeed
        guard resultsA.count >= tests.count / 2 && resultsB.count >= tests.count / 2 else {
            return .failure(.insufficientData("Not enough successful test results"))
        }

        // Build profile
        do {
            let profile = try buildProfile(resultsA: resultsA, resultsB: resultsB, errors: errors)
            if errors.isEmpty {
                return .success(profile)
            } else {
                return .partial(profile, errors)
            }
        } catch {
            return .failure(.calibrationFailed(error.localizedDescription))
        }
    }

    private func runTest(_ test: SyncTest, partner: any LLMPartner, role: PartnerRole) async -> TestResult? {
        let start = ContinuousClock.now

        do {
            let content = try await withTimeout(seconds: timeoutSeconds) {
                try await partner.complete(prompt: test.prompt, system: test.systemPrompt)
            }

            let end = ContinuousClock.now
            let duration = start.duration(to: end)
            let durationMs = Double(duration.components.seconds) * 1000 +
                             Double(duration.components.attoseconds) / 1e15

            let fingerprint = ResponseFingerprint(content: content, latencyMs: durationMs)
            return TestResult(test: test, fingerprint: fingerprint, role: role)

        } catch {
            return nil
        }
    }

    private func buildProfile(resultsA: [TestResult], resultsB: [TestResult], errors: [SyncError]) throws -> SyncProfile {
        let scoreAConscious = scoreForRole(.conscious, results: resultsA)
        let scoreBConscious = scoreForRole(.conscious, results: resultsB)
        let scoreAUnconscious = scoreForRole(.unconscious, results: resultsA)
        let scoreBUnconscious = scoreForRole(.unconscious, results: resultsB)

        // Determine which partner should take which role
        let aIsConscious = scoreAConscious > scoreBConscious

        let roleA: PartnerRole = aIsConscious ? .conscious : .unconscious
        let roleB: PartnerRole = aIsConscious ? .unconscious : .conscious

        let confidenceConscious = max(scoreAConscious, scoreBConscious)
        let confidenceUnconscious = max(scoreAUnconscious, scoreBUnconscious)

        let avgLatencyA = resultsA.map(\.fingerprint.latencyMs).reduce(0, +) / Double(max(resultsA.count, 1))
        let avgLatencyB = resultsB.map(\.fingerprint.latencyMs).reduce(0, +) / Double(max(resultsB.count, 1))
        let latencyDelta = avgLatencyA - avgLatencyB

        let totalConscious = scoreAConscious + scoreBConscious
        let consciousWeightA = totalConscious > 0 ? scoreAConscious / totalConscious : 0.5

        let totalUnconscious = scoreAUnconscious + scoreBUnconscious
        let unconsciousWeightA = totalUnconscious > 0 ? scoreAUnconscious / totalUnconscious : 0.5

        let isInSync = confidenceConscious > 0.6 && confidenceUnconscious > 0.6

        return SyncProfile(
            partnerA: partnerA.metadata,
            partnerB: partnerB.metadata,
            roleA: roleA,
            roleB: roleB,
            confidenceConscious: confidenceConscious,
            confidenceUnconscious: confidenceUnconscious,
            latencyDeltaMs: latencyDelta,
            isInSync: isInSync,
            consciousWeightA: consciousWeightA,
            unconsciousWeightA: unconsciousWeightA,
            testCount: tests.count
        )
    }

    private func scoreForRole(_ role: PartnerRole, results: [TestResult]) -> Float {
        let relevant = results.filter { $0.test.expectedRole == role }
        guard !relevant.isEmpty else { return 0 }

        let scores = relevant.map { result -> Float in
            var score: Float = 0.5 // Base score

            if role == .conscious {
                if result.fingerprint.hasExplanation { score += 0.3 }
                if !result.fingerprint.hasCodeBlocks { score += 0.1 }
            } else {
                if result.fingerprint.hasCodeBlocks { score += 0.4 }
            }

            // Penalty for being too slow
            let expectedLatency: Double = role == .conscious ? 2000 : 1500
            if result.fingerprint.latencyMs > expectedLatency * 2 {
                score -= 0.2
            }

            return max(0, min(1, score)) * result.test.weight
        }

        let totalWeight = relevant.map(\.test.weight).reduce(0, +)
        guard totalWeight > 0 else { return 0 }

        return scores.reduce(0, +) / totalWeight
    }
}

// MARK: - Internal types

private struct TestResult {
    let test: SyncTest
    let fingerprint: ResponseFingerprint
    let role: PartnerRole
}

private struct TimeoutError: Error {}

private func withTimeout<T: Sendable>(seconds: UInt64, operation: @Sendable @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            throw TimeoutError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
