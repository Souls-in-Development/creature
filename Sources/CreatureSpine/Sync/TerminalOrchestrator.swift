import Foundation

/// Routes tasks between two LLM partners based on sync profile.
public actor TerminalOrchestrator {
    private let partnerA: any LLMPartner
    private let partnerB: any LLMPartner
    private var profile: SyncProfile
    private let basisDetector: any BasisDetector

    /// Callback when a task completes
    public var onComplete: (@Sendable (TaskResult) -> Void)?

    public init(
        partnerA: any LLMPartner,
        partnerB: any LLMPartner,
        profile: SyncProfile,
        basisDetector: any BasisDetector = CodeFenceBasisDetector()
    ) {
        self.partnerA = partnerA
        self.partnerB = partnerB
        self.profile = profile
        self.basisDetector = basisDetector
    }

    /// Update the sync profile (e.g., after recalibration).
    public func updateProfile(_ newProfile: SyncProfile) {
        self.profile = newProfile
    }

    /// Execute a task.
    ///
    /// Routing collapses the pair to a single partner, which is right only when one of
    /// them clearly owns the role. When the task is *shared* — `useHybrid` asked for it,
    /// or the calibrated weight sits near 0.5 with the pair in sync — both phases are
    /// read out together instead of one being discarded at the `>= 0.5` threshold.
    public func execute(task: TerminalTask) async -> TaskResult {
        if task.useHybrid || profile.shouldCoordinate(for: task.preferredRole) {
            return await executeHybrid(task: task)
        }

        let start = ContinuousClock.now

        let (targetRole, confidence) = profile.route(for: task.preferredRole)
        let partner = targetRole == profile.roleA ? partnerA : partnerB

        do {
            let response = try await partner.complete(
                prompt: task.prompt,
                system: task.systemPrompt
            )

            let end = ContinuousClock.now
            let duration = start.duration(to: end)
            let latencyMs = Double(duration.components.seconds) * 1000 +
                            Double(duration.components.attoseconds) / 1e15

            let result = TaskResult(
                task: task,
                response: response,
                fromRole: targetRole,
                confidence: confidence,
                latencyMs: latencyMs,
                isSuccess: true
            )

            onComplete?(result)
            return result

        } catch {
            let result = TaskResult(
                task: task,
                response: "",
                fromRole: targetRole,
                confidence: confidence,
                latencyMs: 0,
                isSuccess: false,
                error: error
            )

            onComplete?(result)
            return result
        }
    }

    /// Run both partners on the same prompt, in the same moment, and synthesize.
    ///
    /// Neither conditions on the other — no barrier, no handoff. The two responses are
    /// distinguished by *basis* (prose vs code) and ordered explanation-first.
    public func executeHybrid(task: TerminalTask) async -> TaskResult {
        let start = ContinuousClock.now
        // The routing confidence is what made this a shared task; report it rather than
        // inventing a number.
        let (_, routedConfidence) = profile.route(for: task.preferredRole)

        async let responseATask = partnerA.complete(prompt: task.prompt, system: task.systemPrompt)
        async let responseBTask = partnerB.complete(prompt: task.prompt, system: task.systemPrompt)

        do {
            let (responseA, responseB) = try await (responseATask, responseBTask)

            let end = ContinuousClock.now
            let duration = start.duration(to: end)
            let latencyMs = Double(duration.components.seconds) * 1000 +
                            Double(duration.components.attoseconds) / 1e15

            // Synthesize by BASIS, not by sniffing the string: whichever partner answered
            // in code contributes its RESOLVED source, and explanation comes first.
            let basisA = basisDetector.basis(of: responseA)
            let basisB = basisDetector.basis(of: responseB)
            let textA = basisA.codePayload ?? responseA
            let textB = basisB.codePayload ?? responseB

            let synthesized: String
            switch (basisA, basisB) {
            case (.code, .words): synthesized = textB + "\n\n" + textA
            case (.words, .code): synthesized = textA + "\n\n" + textB
            default:              synthesized = textA + "\n\n---\n\n" + textB
            }

            let result = TaskResult(
                task: task,
                response: synthesized,
                fromRole: task.preferredRole,
                confidence: routedConfidence,
                latencyMs: latencyMs,
                isSuccess: true,
                isCoordinated: true
            )

            onComplete?(result)
            return result

        } catch {
            return TaskResult(
                task: task,
                response: "",
                fromRole: task.preferredRole,
                confidence: 0,
                latencyMs: 0,
                isSuccess: false,
                error: error,
                isCoordinated: true
            )
        }
    }

    /// Which partner is calibrated as the unconscious — the one that cites.
    private var unconsciousPartner: any LLMPartner {
        profile.roleA == .unconscious ? partnerA : partnerB
    }

    private var consciousPartner: any LLMPartner {
        profile.roleA == .conscious ? partnerA : partnerB
    }

    /// Coordinate, then let the compiler adjudicate the code phase.
    ///
    /// The conscious answers once, in words. The unconscious cites; if the citation does
    /// not type-check, the compiler's own messages are handed straight back and it cites
    /// again, up to `maxAttempts`. Nothing is certified without an affirmative compile —
    /// an unavailable toolchain ends the loop immediately rather than retrying against a
    /// judge that cannot judge.
    public func executeCited(
        task: TerminalTask,
        verifier: any CodeVerifier,
        maxAttempts: Int = 3
    ) async -> TaskResult {
        let start = ContinuousClock.now
        let (_, routedConfidence) = profile.route(for: task.preferredRole)

        // The conscious phase runs once — words do not need recompiling.
        let words: String
        do {
            words = try await consciousPartner.complete(prompt: task.prompt, system: task.systemPrompt)
        } catch {
            return TaskResult(task: task, response: "", fromRole: task.preferredRole,
                              confidence: 0, latencyMs: 0, isSuccess: false, error: error,
                              isCoordinated: true)
        }

        var prompt = task.prompt
        var attempts = 0
        var lastVerdict: VerifierVerdict?
        var lastSource = ""

        while attempts < max(1, maxAttempts) {
            attempts += 1

            let cited: String
            do {
                cited = try await unconsciousPartner.complete(prompt: prompt, system: task.systemPrompt)
            } catch {
                return TaskResult(task: task, response: "", fromRole: task.preferredRole,
                                  confidence: 0, latencyMs: 0, isSuccess: false, error: error,
                                  isCoordinated: true, verification: lastVerdict, attempts: attempts)
            }

            // A word-basis reply from the unconscious is nothing to compile; take it as-is.
            guard let source = basisDetector.basis(of: cited).codePayload else {
                lastSource = cited
                break
            }
            lastSource = source

            let verdict = await verifier.verify(source: source)
            lastVerdict = verdict

            if verdict.clean || verdict.unavailableReason != nil { break }

            // Hand the compiler's own words back. This is the wince that teaches the accent.
            prompt = """
            \(task.prompt)

            Your previous citation did not type-check. The compiler said:
            \(verdict.messages.joined(separator: "\n"))

            Cite again so that it compiles.
            """
        }

        let end = ContinuousClock.now
        let duration = start.duration(to: end)
        let latencyMs = Double(duration.components.seconds) * 1000 +
                        Double(duration.components.attoseconds) / 1e15

        let result = TaskResult(
            task: task,
            response: words + "\n\n" + lastSource,
            fromRole: task.preferredRole,
            confidence: routedConfidence,
            latencyMs: latencyMs,
            isSuccess: true,
            isCoordinated: true,
            verification: lastVerdict,
            attempts: attempts
        )
        onComplete?(result)
        return result
    }
}

/// A task to execute in the terminal.
public struct TerminalTask: Sendable {
    public let id: String
    public let prompt: String
    public let systemPrompt: String?
    public let preferredRole: PartnerRole
    public let useHybrid: Bool

    public init(
        id: String = UUID().uuidString,
        prompt: String,
        systemPrompt: String? = nil,
        preferredRole: PartnerRole = .conscious,
        useHybrid: Bool = false
    ) {
        self.id = id
        self.prompt = prompt
        self.systemPrompt = systemPrompt
        self.preferredRole = preferredRole
        self.useHybrid = useHybrid
    }
}

/// Result of executing a terminal task.
public struct TaskResult: Sendable {
    public let task: TerminalTask
    public let response: String
    public let fromRole: PartnerRole
    public let confidence: Float
    public let latencyMs: Double
    public let isSuccess: Bool
    public let error: Error?

    /// True when both partners ran on this task and their phases were synthesized,
    /// rather than the pair being collapsed to a single partner by routing.
    public let isCoordinated: Bool

    /// The compiler's verdict on the code phase, when a verifier adjudicated it.
    public let verification: VerifierVerdict?

    /// How many times the unconscious was asked. 1 unless it had to re-cite.
    public let attempts: Int

    public init(
        task: TerminalTask,
        response: String,
        fromRole: PartnerRole,
        confidence: Float,
        latencyMs: Double,
        isSuccess: Bool,
        error: Error? = nil,
        isCoordinated: Bool = false,
        verification: VerifierVerdict? = nil,
        attempts: Int = 1
    ) {
        self.task = task
        self.response = response
        self.fromRole = fromRole
        self.confidence = confidence
        self.latencyMs = latencyMs
        self.isSuccess = isSuccess
        self.error = error
        self.isCoordinated = isCoordinated
        self.verification = verification
        self.attempts = attempts
    }
}
