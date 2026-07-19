import Testing
@testable import CreatureSpine

@Test func coordinateClamps() {
    let c = SpineCoordinate(ra: 400, dec: -100, alt: -5)
    #expect(c.ra == 360)
    #expect(c.dec == -90)
    #expect(c.alt == 0)
}

@Test func coordinateStringKey() {
    let c = SpineCoordinate(ra: 45.0, dec: 30.0, alt: 5)
    #expect(c.stringKey == "45.0,30.0,5")
}

@Test func angularDistanceSamePoint() {
    let c = SpineCoordinate(ra: 45, dec: 30, alt: 5)
    #expect(c.angularDistance(to: c) < 0.001)
}

@Test func angularDistanceKnownValue() {
    let a = SpineCoordinate(ra: 0, dec: 0, alt: 0)
    let b = SpineCoordinate(ra: 0, dec: 90, alt: 0)
    let dist = a.angularDistance(to: b)
    #expect(abs(dist - 90.0) < 0.01)
}
