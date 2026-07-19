import Testing
@testable import CreatureTrunk

@Suite struct ReadinessMixerTests {

    /// Both Swift and Python hold → colour emerges from the mix (partially
    /// desaturated — the two hues are ~170° apart so coherence is ~0.9, not
    /// fully white, but less saturated than a single hold).
    @Test func bothHoldingGrammarsMixToWhite() {
        let readiness = NodeReadiness(verdicts: [
            "swift": .holds,
            "python": .holds
        ])
        let colour = ReadinessMixer.mix(readiness)
        #expect(colour != nil)
        // Less saturated than a single hold (0.75) — proves mixing happened.
        #expect(colour!.saturation < 0.75)
        // Still bright — both tracks are full energy.
        #expect(colour!.value > 0.7)
        // Hue is a blend, not exactly either grammar's hue.
        let swiftHue = TrunkColour.hueForLanguage("swift")
        let pythonHue = TrunkColour.hueForLanguage("python")
        #expect(colour!.hue != swiftHue)
        #expect(colour!.hue != pythonHue)
    }

    /// Swift holds, Python broken → Swift's hue, but saturation diluted because
    /// the mixer averages over ALL tracks (including the zero-energy broken one).
    @Test func oneBrokenShiftsToHoldersChroma() {
        let readiness = NodeReadiness(verdicts: [
            "swift": .holds,
            "python": .broken
        ])
        let colour = ReadinessMixer.mix(readiness)
        #expect(colour != nil)
        // Hue is Swift's — only Swift contributes non-zero energy.
        let swiftHue = TrunkColour.hueForLanguage("swift")
        #expect(colour!.hue == swiftHue)
        // Saturation is diluted: avg of 0.75 (hold) and 0 (broken) = 0.375.
        #expect(colour!.saturation > 0.3)
        #expect(colour!.saturation < 0.75)
    }

    /// Swift holds, Python unprobed → same as broken: zero-energy track dilutes
    /// saturation but does not change hue.
    @Test func oneUnprobedIsZeroEnergyNeverWhite() {
        let readiness = NodeReadiness(verdicts: [
            "swift": .holds,
            "python": .unprobed
        ])
        let colour = ReadinessMixer.mix(readiness)
        #expect(colour != nil)
        // Hue is Swift's — unprobed contributes zero energy.
        let swiftHue = TrunkColour.hueForLanguage("swift")
        #expect(colour!.hue == swiftHue)
        // Not white — saturation is diluted, not zero.
        #expect(colour!.saturation > 0.3)
        #expect(colour!.saturation < 0.75)
    }

    /// Both broken → no holds, no chroma (nil = no signal).
    @Test func allBrokenReturnsNil() {
        let readiness = NodeReadiness(verdicts: [
            "swift": .broken,
            "python": .broken
        ])
        let colour = ReadinessMixer.mix(readiness)
        #expect(colour == nil)
    }

    /// All unprobed → no holds, no chroma (nil = no signal).
    @Test func allUnprobedReturnsNil() {
        let readiness = NodeReadiness(verdicts: [
            "swift": .unprobed,
            "python": .unprobed
        ])
        let colour = ReadinessMixer.mix(readiness)
        #expect(colour == nil)
    }

    /// Single grammar hold → pure hue.
    @Test func singleGrammarHoldIsPureHue() {
        let readiness = NodeReadiness(verdicts: ["swift": .holds])
        let colour = ReadinessMixer.mix(readiness)
        #expect(colour != nil)
        #expect(colour!.saturation > 0.5)
    }
}
