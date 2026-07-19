import Testing
@testable import CreatureSpine

@Suite struct CodeVerifierTests {
    @Test func unavailableIsNeverClean() {
        let v = VerifierVerdict.unavailable("no toolchain")
        #expect(!v.clean)                       // THE BOUND: only an affirmative pass earns clean
        #expect(v.unavailableReason == "no toolchain")
        #expect(v.messages.isEmpty)
    }

    @Test func cleanVerdictCarriesNoMessages() {
        let v = VerifierVerdict(clean: true, messages: [])
        #expect(v.clean)
        #expect(v.unavailableReason == nil)
    }

    @Test func failedVerdictCarriesCompilerMessages() {
        let v = VerifierVerdict(clean: false, messages: ["3: cannot find 'foo' in scope"])
        #expect(!v.clean)
        #expect(v.messages.count == 1)
    }
}
