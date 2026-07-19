import Testing
@testable import CreatureSpine

@Test func bridgeFromCognitiveCoordinate() {
    let bridge = CoordinateBridge.fromCognitive(ra: 45.0, dec: 30.0, alt: 5.7)
    #expect(bridge.ra == 45.0)
    #expect(bridge.dec == 30.0)
    #expect(bridge.alt == 6) // Rounds to nearest Int
}

@Test func bridgeFromCognitiveCoordinateZeroAlt() {
    let bridge = CoordinateBridge.fromCognitive(ra: 0, dec: 0, alt: 0.0)
    #expect(bridge.alt == 0)
}

@Test func bridgeToCognitiveCoordinate() {
    let coord = SpineCoordinate(ra: 45.0, dec: 30.0, alt: 5)
    let (ra, dec, alt) = CoordinateBridge.toCognitive(coord)
    #expect(ra == 45.0)
    #expect(dec == 30.0)
    #expect(alt == 5.0)
}

@Test func bridgeRoundTrip() {
    let original = SpineCoordinate(ra: 210.5, dec: -45.3, alt: 12)
    let (ra, dec, alt) = CoordinateBridge.toCognitive(original)
    let roundTripped = CoordinateBridge.fromCognitive(ra: ra, dec: dec, alt: alt)
    #expect(roundTripped == original)
}

@Test func bridgeClampsValues() {
    let bridge = CoordinateBridge.fromCognitive(ra: 400.0, dec: -100.0, alt: -5.0)
    #expect(bridge.ra == 360.0)
    #expect(bridge.dec == -90.0)
    #expect(bridge.alt == 0)
}
