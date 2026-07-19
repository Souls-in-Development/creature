import Testing
@testable import CreatureSpine

@Test func colourTrackClamps() {
    let marking = CreatureMarking(name: "scout", pattern: 0)
    let track = ColourTrack(
        coordinate: .origin,
        hue: 400.0,
        saturation: 1.5,
        value: -0.1,
        creatureMarking: marking
    )
    #expect(track.hue == 360.0)
    #expect(track.saturation == 1.0)
    #expect(track.value == 0.0)
}

@Test func colourTrackFromDaemonKey() {
    let marking = CreatureMarking(name: "scout", pattern: 0)
    let track = ColourTrack.fromReaction(
        coordinate: .origin,
        daemonKeyHue: 210.0,
        reactionIntensity: 0.7,
        energy: 0.9,
        creatureMarking: marking
    )
    #expect(abs(track.hue - 210.0) < 0.001)
    #expect(abs(track.saturation - 0.7) < 0.001)
    #expect(abs(track.value - 0.9) < 0.001)
}
