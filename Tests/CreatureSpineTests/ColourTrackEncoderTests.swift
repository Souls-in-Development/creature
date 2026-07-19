import Testing
@testable import CreatureSpine

@Test func encodeBasicTrack() {
    let track = ColourTrack.fromReaction(
        coordinate: .origin,
        daemonKeyHue: 180.0,
        reactionIntensity: 0.5,
        energy: 0.8,
        creatureMarking: CreatureMarking(name: "test", pattern: 128)
    )
    let encoded = ColourTrackEncoder.encode(track)

    #expect(abs(encoded.x - 0.5) < 0.01)       // hue 180/360 = 0.5
    #expect(abs(encoded.y - 0.5) < 0.01)       // saturation
    #expect(abs(encoded.z - 0.8) < 0.01)       // value
    #expect(abs(encoded.w - 128.0/255.0) < 0.01) // pattern
}

@Test func encodeZeroHue() {
    let track = ColourTrack.fromReaction(
        coordinate: .origin,
        daemonKeyHue: 0.0,
        reactionIntensity: 1.0,
        energy: 1.0,
        creatureMarking: CreatureMarking(name: "test", pattern: 0)
    )
    let encoded = ColourTrackEncoder.encode(track)
    #expect(encoded.x == 0.0)
    #expect(encoded.y == 1.0)
    #expect(encoded.z == 1.0)
    #expect(encoded.w == 0.0)
}

@Test func encodeMaxValues() {
    let track = ColourTrack.fromReaction(
        coordinate: .origin,
        daemonKeyHue: 360.0,
        reactionIntensity: 1.0,
        energy: 1.0,
        creatureMarking: CreatureMarking(name: "test", pattern: 255)
    )
    let encoded = ColourTrackEncoder.encode(track)
    #expect(abs(encoded.x - 1.0) < 0.01)
    #expect(encoded.y == 1.0)
    #expect(encoded.z == 1.0)
    #expect(abs(encoded.w - 1.0) < 0.01)
}

@Test func decodeRoundTrip() {
    let track = ColourTrack.fromReaction(
        coordinate: .origin,
        daemonKeyHue: 120.0,
        reactionIntensity: 0.7,
        energy: 0.85,
        creatureMarking: CreatureMarking(name: "test", pattern: 42)
    )
    let encoded = ColourTrackEncoder.encode(track)
    let decoded = ColourTrackEncoder.decode(encoded)

    #expect(abs(decoded.hue - 120.0) < 1.0)
    #expect(abs(decoded.saturation - 0.7) < 0.01)
    #expect(abs(decoded.value - 0.85) < 0.01)
    #expect(decoded.pattern == 42)
}

@Test func decodeMidrangeValues() {
    let pixel = SIMD4<Float>(0.25, 0.6, 0.4, 0.5)
    let decoded = ColourTrackEncoder.decode(pixel)

    #expect(abs(decoded.hue - 90.0) < 1.0)        // 0.25 * 360
    #expect(abs(decoded.saturation - 0.6) < 0.01)
    #expect(abs(decoded.value - 0.4) < 0.01)
    #expect(decoded.pattern == 128)                 // round(0.5 * 255)
}

@Test func encodeFromDirtyEntry() {
    let entry = DirtyEntry(
        coordinate: SpineCoordinate(ra: 45.0, dec: 30.0, alt: 3),
        density: 0.72,
        averageHue: 200.0,
        dominantMarking: CreatureMarking(name: "test", pattern: 50)
    )
    let encoded = ColourTrackEncoder.encodeEntry(entry)

    #expect(abs(encoded.x - 200.0/360.0) < 0.01)  // hue
    #expect(abs(encoded.y - 0.72) < 0.01)           // density as saturation
    #expect(encoded.z > 0)                            // value from density
    #expect(abs(encoded.w - 50.0/255.0) < 0.01)     // pattern
}

@Test func encodeEntryNilHue() {
    let entry = DirtyEntry(
        coordinate: SpineCoordinate(ra: 45.0, dec: 30.0, alt: 3),
        density: 0.5,
        averageHue: nil,
        dominantMarking: nil
    )
    let encoded = ColourTrackEncoder.encodeEntry(entry)

    #expect(encoded.x == 0.0)   // nil hue → 0
    #expect(encoded.w == 0.0)   // nil marking → pattern 0
}
