import Testing
@testable import CreatureSpine

@Test func authenticatedViewPreservesAllFields() {
    let original = ColourTrack.fromReaction(
        coordinate: .origin,
        daemonKeyHue: 120.0,
        reactionIntensity: 0.9,
        energy: 0.8,
        creatureMarking: CreatureMarking(name: "myAI", pattern: 42)
    )
    let view = TwoSidedPaper.view(for: original, auth: .authenticated)

    #expect(view.hue == original.hue)
    #expect(view.saturation == original.saturation)
    #expect(view.value == original.value)
    #expect(view.creatureMarking.name == "myAI")
    #expect(view.creatureMarking.pattern == 42)
    #expect(view.coordinate == original.coordinate)
}

@Test func unauthenticatedViewDesaturates() {
    let original = ColourTrack.fromReaction(
        coordinate: .origin,
        daemonKeyHue: 120.0,
        reactionIntensity: 0.9,
        energy: 0.8,
        creatureMarking: CreatureMarking(name: "myAI", pattern: 42)
    )
    let view = TwoSidedPaper.view(for: original, auth: .unauthenticated)

    // Saturation reduced to 30%
    #expect(abs(view.saturation - original.saturation * 0.3) < 0.01)
    // Value preserved
    #expect(view.value == original.value)
}

@Test func unauthenticatedViewPreservesHue() {
    let original = ColourTrack.fromReaction(
        coordinate: .origin,
        daemonKeyHue: 240.0,
        reactionIntensity: 0.7,
        energy: 0.6,
        creatureMarking: CreatureMarking(name: "myAI", pattern: 42)
    )
    let view = TwoSidedPaper.view(for: original, auth: .unauthenticated)

    // Hue preserved — pattern still recognizable
    #expect(view.hue == original.hue)
}

@Test func unauthenticatedViewAnonymizesMarking() {
    let original = ColourTrack.fromReaction(
        coordinate: .origin,
        daemonKeyHue: 120.0,
        reactionIntensity: 0.9,
        energy: 0.8,
        creatureMarking: CreatureMarking(name: "myAI", pattern: 42)
    )
    let view = TwoSidedPaper.view(for: original, auth: .unauthenticated)

    #expect(view.creatureMarking.name == "unknown")
    #expect(view.creatureMarking.pattern == 0)
}

@Test func patternRecognitionSucceedsThroughTint() {
    let original = ColourTrack.fromReaction(
        coordinate: .origin,
        daemonKeyHue: 120.0,
        reactionIntensity: 0.9,
        energy: 0.8,
        creatureMarking: CreatureMarking(name: "myAI", pattern: 42)
    )
    let tinted = TwoSidedPaper.view(for: original, auth: .unauthenticated)
    let recognized = TwoSidedPaper.verifyPatternRecognition(canonical: original, tinted: tinted)
    #expect(recognized)
}

@Test func patternRecognitionFailsForDifferentHue() {
    let original = ColourTrack.fromReaction(
        coordinate: .origin,
        daemonKeyHue: 120.0,
        reactionIntensity: 0.9,
        energy: 0.8,
        creatureMarking: CreatureMarking(name: "myAI", pattern: 42)
    )
    let impostor = ColourTrack.fromReaction(
        coordinate: .origin,
        daemonKeyHue: 300.0,  // Very different hue
        reactionIntensity: 0.27,  // Matches tinted saturation
        energy: 0.8,
        creatureMarking: CreatureMarking(name: "unknown", pattern: 0)
    )
    let recognized = TwoSidedPaper.verifyPatternRecognition(canonical: original, tinted: impostor)
    #expect(!recognized)
}

@Test func batchTintMultipleTracks() {
    let tracks = (0..<5).map { i in
        ColourTrack.fromReaction(
            coordinate: SpineCoordinate(ra: Double(i) * 72.0, dec: 0.0, alt: 1),
            daemonKeyHue: Float(i) * 72.0,
            reactionIntensity: 0.8,
            energy: 0.9,
            creatureMarking: CreatureMarking(name: "c\(i)", pattern: UInt8(i))
        )
    }
    let tinted = TwoSidedPaper.batchView(for: tracks, auth: .unauthenticated)

    #expect(tinted.count == 5)
    for (i, view) in tinted.enumerated() {
        #expect(view.hue == tracks[i].hue)  // Hue preserved
        #expect(view.creatureMarking.name == "unknown")  // Anonymized
    }
}

@Test func simd4EncodingRespectsTint() {
    let original = ColourTrack.fromReaction(
        coordinate: .origin,
        daemonKeyHue: 180.0,
        reactionIntensity: 1.0,
        energy: 1.0,
        creatureMarking: CreatureMarking(name: "myAI", pattern: 100)
    )
    let tinted = TwoSidedPaper.view(for: original, auth: .unauthenticated)

    let canonicalPixel = ColourTrackEncoder.encode(original)
    let tintedPixel = ColourTrackEncoder.encode(tinted)

    // Same hue channel
    #expect(abs(canonicalPixel.x - tintedPixel.x) < 0.01)
    // Tinted saturation much lower
    #expect(tintedPixel.y < canonicalPixel.y * 0.5)
    // Pattern anonymized
    #expect(tintedPixel.w == 0.0)
}
