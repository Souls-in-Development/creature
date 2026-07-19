import Testing
@testable import CreatureSpine

@Test func emptyMixerReturnsNil() {
    let mixer = AdditiveMixer()
    #expect(mixer.mix() == nil)
}

@Test func singleTrackPassthrough() {
    let track = ColourTrack.fromReaction(
        coordinate: .origin,
        daemonKeyHue: 120.0,
        reactionIntensity: 0.8,
        energy: 0.9,
        creatureMarking: CreatureMarking(name: "test", pattern: 1)
    )
    var mixer = AdditiveMixer()
    mixer.add(track)
    let result = mixer.mix()

    #expect(result != nil)
    #expect(result!.hue == 120.0)
    #expect(result!.saturation == 0.8)
    #expect(result!.value == 0.9)
}

@Test func sameHueReinforces() {
    var mixer = AdditiveMixer()
    for _ in 0..<3 {
        mixer.add(ColourTrack.fromReaction(
            coordinate: .origin,
            daemonKeyHue: 120.0,
            reactionIntensity: 0.6,
            energy: 0.7,
            creatureMarking: CreatureMarking(name: "a", pattern: 1)
        ))
    }
    let result = mixer.mix()!

    // Same hue → saturation stays high (reinforcement)
    #expect(result.hue >= 115 && result.hue <= 125)
    #expect(result.saturation >= 0.5)
}

@Test func differentHuesDesaturate() {
    var mixer = AdditiveMixer()
    // Add 5 evenly-spaced hues → should desaturate toward white
    for i in 0..<5 {
        mixer.add(ColourTrack.fromReaction(
            coordinate: .origin,
            daemonKeyHue: Float(i) * 72.0,  // 0, 72, 144, 216, 288
            reactionIntensity: 1.0,
            energy: 1.0,
            creatureMarking: CreatureMarking(name: "c\(i)", pattern: UInt8(i))
        ))
    }
    let result = mixer.mix()!

    // Diverse hues → low saturation (overload → white)
    #expect(result.saturation < 0.3)
    #expect(result.value > 0.8)
}

@Test func twoOppositeHuesDesaturate() {
    var mixer = AdditiveMixer()
    mixer.add(ColourTrack.fromReaction(
        coordinate: .origin,
        daemonKeyHue: 0.0,
        reactionIntensity: 1.0, energy: 1.0,
        creatureMarking: CreatureMarking(name: "a", pattern: 1)
    ))
    mixer.add(ColourTrack.fromReaction(
        coordinate: .origin,
        daemonKeyHue: 180.0,
        reactionIntensity: 1.0, energy: 1.0,
        creatureMarking: CreatureMarking(name: "b", pattern: 2)
    ))
    let result = mixer.mix()!

    // Opposite hues → strong desaturation
    #expect(result.saturation < 0.4)
}

@Test func zeroEnergyTrackIgnored() {
    var mixer = AdditiveMixer()
    mixer.add(ColourTrack.fromReaction(
        coordinate: .origin,
        daemonKeyHue: 120.0,
        reactionIntensity: 0.0, energy: 0.0,
        creatureMarking: CreatureMarking(name: "dead", pattern: 0)
    ))
    mixer.add(ColourTrack.fromReaction(
        coordinate: .origin,
        daemonKeyHue: 60.0,
        reactionIntensity: 0.8, energy: 0.9,
        creatureMarking: CreatureMarking(name: "alive", pattern: 1)
    ))
    let result = mixer.mix()!

    // Zero-energy track has no weight → result is dominated by alive track
    #expect(result.hue >= 55 && result.hue <= 65)
}

@Test func mixerResets() {
    var mixer = AdditiveMixer()
    mixer.add(ColourTrack.fromReaction(
        coordinate: .origin,
        daemonKeyHue: 120.0,
        reactionIntensity: 0.8, energy: 0.9,
        creatureMarking: CreatureMarking(name: "test", pattern: 1)
    ))
    mixer.reset()
    #expect(mixer.mix() == nil)
}
