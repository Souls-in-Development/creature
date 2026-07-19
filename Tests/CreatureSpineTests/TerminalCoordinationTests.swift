import Testing
@testable import CreatureSpine

/// Records which partners actually ran — the whole point is whether both phases were
/// read out or one was discarded at the routing threshold.
private actor CallLog {
    private(set) var calls: [String] = []
    func record(_ name: String) { calls.append(name) }
}

private struct StubPartner: LLMPartner {
    let metadata: PartnerMetadata
    let reply: String
    let log: CallLog

    func complete(prompt: String, system: String?) async throws -> String {
        await log.record(metadata.name)
        return reply
    }
}

private func meta(_ name: String, _ role: PartnerRole) -> PartnerMetadata {
    PartnerMetadata(name: name, provider: "test", preferredRole: role, latencyMs: 10)
}

private func makeProfile(consciousWeightA: Float, inSync: Bool) -> SyncProfile {
    SyncProfile(
        partnerA: meta("A", .conscious),
        partnerB: meta("B", .unconscious),
        roleA: .conscious,
        roleB: .unconscious,
        confidenceConscious: 0.8,
        confidenceUnconscious: 0.8,
        latencyDeltaMs: 0,
        isInSync: inSync,
        consciousWeightA: consciousWeightA,
        unconsciousWeightA: 0.5,
        testCount: 4
    )
}

@Suite struct TerminalCoordinationTests {

    @Test func shouldCoordinateOnlyWhenInSyncAndContested() {
        // Contested (weight ≈ 0.5) and spanning both bases → the pair shares the task.
        #expect(makeProfile(consciousWeightA: 0.50, inSync: true).shouldCoordinate(for: .conscious))
        #expect(makeProfile(consciousWeightA: 0.55, inSync: true).shouldCoordinate(for: .conscious))
        // One partner clearly owns it → collapse is correct.
        #expect(!makeProfile(consciousWeightA: 0.95, inSync: true).shouldCoordinate(for: .conscious))
        #expect(!makeProfile(consciousWeightA: 0.05, inSync: true).shouldCoordinate(for: .conscious))
        // Out of sync → the two phases aren't of the same state; coordination is meaningless.
        #expect(!makeProfile(consciousWeightA: 0.50, inSync: false).shouldCoordinate(for: .conscious))
    }

    @Test func sharedTaskReadsOutBothPhases() async {
        let log = CallLog()
        let a = StubPartner(metadata: meta("A", .conscious), reply: "because X follows Y", log: log)
        let b = StubPartner(metadata: meta("B", .unconscious), reply: "```swift\nlet x = 1\n```", log: log)
        let orch = TerminalOrchestrator(partnerA: a, partnerB: b, profile: makeProfile(consciousWeightA: 0.5, inSync: true))

        let result = await orch.execute(task: TerminalTask(prompt: "p", preferredRole: .conscious))

        // Both brains ran, in the same moment — no partner discarded.
        #expect(await Set(log.calls) == ["A", "B"])
        #expect(result.isCoordinated)
        #expect(result.response.contains("because X follows Y"))
        #expect(result.response.contains("let x = 1"))
    }

    @Test func decisiveTaskCollapsesToOnePartner() async {
        let log = CallLog()
        let a = StubPartner(metadata: meta("A", .conscious), reply: "A", log: log)
        let b = StubPartner(metadata: meta("B", .unconscious), reply: "B", log: log)
        let orch = TerminalOrchestrator(partnerA: a, partnerB: b, profile: makeProfile(consciousWeightA: 0.95, inSync: true))

        let result = await orch.execute(task: TerminalTask(prompt: "p", preferredRole: .conscious))

        // One partner clearly owns the role — routing is right, and cheaper.
        #expect(await log.calls == ["A"])
        #expect(!result.isCoordinated)
    }

    @Test func outOfSyncFallsBackToRouting() async {
        let log = CallLog()
        let a = StubPartner(metadata: meta("A", .conscious), reply: "A", log: log)
        let b = StubPartner(metadata: meta("B", .unconscious), reply: "B", log: log)
        // Contested weight, but the pair does not span both bases.
        let orch = TerminalOrchestrator(partnerA: a, partnerB: b, profile: makeProfile(consciousWeightA: 0.5, inSync: false))

        let result = await orch.execute(task: TerminalTask(prompt: "p", preferredRole: .conscious))

        #expect(await log.calls == ["A"])
        #expect(!result.isCoordinated)
    }

    @Test func useHybridForcesCoordinationEvenWhenDecisive() async {
        let log = CallLog()
        let a = StubPartner(metadata: meta("A", .conscious), reply: "A", log: log)
        let b = StubPartner(metadata: meta("B", .unconscious), reply: "B", log: log)
        let orch = TerminalOrchestrator(partnerA: a, partnerB: b, profile: makeProfile(consciousWeightA: 0.95, inSync: true))

        // The switch that had no wire behind it.
        let result = await orch.execute(task: TerminalTask(prompt: "p", preferredRole: .conscious, useHybrid: true))

        #expect(await Set(log.calls) == ["A", "B"])
        #expect(result.isCoordinated)
    }

    /// A detector that treats "KEYS:" prefixed responses as code resolving to fixed source.
    private struct StubDetector: BasisDetector {
        func basis(of response: String) -> ResponseBasis {
            response.hasPrefix("KEYS:") ? .code("RESOLVED SOURCE") : .words
        }
    }

    @Test func synthesisUsesTheResolvedCodePhaseNotTheCitation() async {
        let log = CallLog()
        let a = StubPartner(metadata: meta("A", .conscious), reply: "the reasoning", log: log)
        let b = StubPartner(metadata: meta("B", .unconscious), reply: "KEYS:^abc", log: log)
        let orch = TerminalOrchestrator(
            partnerA: a, partnerB: b,
            profile: makeProfile(consciousWeightA: 0.5, inSync: true),
            basisDetector: StubDetector()
        )

        let result = await orch.execute(task: TerminalTask(prompt: "p", preferredRole: .conscious))

        #expect(result.isCoordinated)
        #expect(result.response.hasPrefix("the reasoning"))    // explanation first
        #expect(result.response.contains("RESOLVED SOURCE"))   // the resolved source, not "^abc"
        #expect(!result.response.contains("^abc"))
    }

    @Test func synthesisOrdersExplanationBeforeCode() async {
        let log = CallLog()
        // A speaks in the code basis, B in the prose basis — the readout must reorder them.
        let a = StubPartner(metadata: meta("A", .conscious), reply: "```swift\nlet x = 1\n```", log: log)
        let b = StubPartner(metadata: meta("B", .unconscious), reply: "first, the reasoning", log: log)
        let orch = TerminalOrchestrator(partnerA: a, partnerB: b, profile: makeProfile(consciousWeightA: 0.5, inSync: true))

        let result = await orch.execute(task: TerminalTask(prompt: "p", preferredRole: .conscious))

        #expect(result.response.hasPrefix("first, the reasoning"))
        #expect(result.response.contains("```swift"))
    }

    // MARK: - executeCited: the compiler adjudicates

    /// A partner whose reply changes on each call, so we can watch a retry happen.
    private actor ScriptedPartnerBox {
        var replies: [String]
        init(_ r: [String]) { replies = r }
        func next() -> String { replies.isEmpty ? "" : replies.removeFirst() }
    }

    private struct ScriptedPartner: LLMPartner {
        let metadata: PartnerMetadata
        let box: ScriptedPartnerBox
        let log: CallLog
        func complete(prompt: String, system: String?) async throws -> String {
            await log.record(prompt)
            return await box.next()
        }
    }

    /// Rejects the first source, accepts anything containing "fixed".
    private struct PickyVerifier: CodeVerifier {
        let language = "swift"
        func verify(source: String) async -> VerifierVerdict {
            source.contains("fixed")
                ? VerifierVerdict(clean: true, messages: [])
                : VerifierVerdict(clean: false, messages: ["line 1: cannot find 'foo' in scope"])
        }
    }

    private struct PassthroughDetector: BasisDetector {
        func basis(of response: String) -> ResponseBasis {
            response.hasPrefix("CODE:") ? .code(String(response.dropFirst(5))) : .words
        }
    }

    @Test func compilerErrorIsFedBackAndTheUnconsciousRecites() async {
        let log = CallLog()
        let conscious = StubPartner(metadata: meta("A", .conscious), reply: "the reasoning", log: log)
        let box = ScriptedPartnerBox(["CODE:foo()", "CODE:fixed()"])
        let unconscious = ScriptedPartner(metadata: meta("B", .unconscious), box: box, log: log)

        let orch = TerminalOrchestrator(
            partnerA: conscious, partnerB: unconscious,
            profile: makeProfile(consciousWeightA: 0.5, inSync: true),
            basisDetector: PassthroughDetector()
        )

        let result = await orch.executeCited(
            task: TerminalTask(prompt: "p", preferredRole: .conscious),
            verifier: PickyVerifier(),
            maxAttempts: 3
        )

        #expect(result.isSuccess)
        #expect(result.attempts == 2)                      // one rejection, one re-citation
        #expect(result.verification?.clean == true)
        #expect(result.response.contains("fixed()"))
        // The compiler's own words were handed back verbatim.
        let prompts = await log.calls
        #expect(prompts.contains { $0.contains("cannot find 'foo' in scope") })
    }

    @Test func exhaustingAttemptsReturnsTheLastUncleanVerdict() async {
        let log = CallLog()
        let conscious = StubPartner(metadata: meta("A", .conscious), reply: "reasoning", log: log)
        let box = ScriptedPartnerBox(["CODE:foo()", "CODE:foo()", "CODE:foo()"])
        let unconscious = ScriptedPartner(metadata: meta("B", .unconscious), box: box, log: log)

        let orch = TerminalOrchestrator(
            partnerA: conscious, partnerB: unconscious,
            profile: makeProfile(consciousWeightA: 0.5, inSync: true),
            basisDetector: PassthroughDetector()
        )

        let result = await orch.executeCited(
            task: TerminalTask(prompt: "p", preferredRole: .conscious),
            verifier: PickyVerifier(),
            maxAttempts: 2
        )

        #expect(result.attempts == 2)
        #expect(result.verification?.clean == false)
        #expect(result.isSuccess)     // we still return the work; we just don't certify it
    }

    /// An unavailable toolchain must not loop and must not certify.
    @Test func unavailableVerifierDoesNotRetry() async {
        struct AbsentVerifier: CodeVerifier {
            let language = "swift"
            func verify(source: String) async -> VerifierVerdict { .unavailable("no swiftc") }
        }
        let log = CallLog()
        let conscious = StubPartner(metadata: meta("A", .conscious), reply: "reasoning", log: log)
        let unconscious = StubPartner(metadata: meta("B", .unconscious), reply: "CODE:foo()", log: log)

        let orch = TerminalOrchestrator(
            partnerA: conscious, partnerB: unconscious,
            profile: makeProfile(consciousWeightA: 0.5, inSync: true),
            basisDetector: PassthroughDetector()
        )

        let result = await orch.executeCited(
            task: TerminalTask(prompt: "p", preferredRole: .conscious),
            verifier: AbsentVerifier(), maxAttempts: 3
        )

        #expect(result.attempts == 1)                            // no retry against an absent judge
        #expect(result.verification?.clean == false)
        #expect(result.verification?.unavailableReason == "no swiftc")
    }
}
