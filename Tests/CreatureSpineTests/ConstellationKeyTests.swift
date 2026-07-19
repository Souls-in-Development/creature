import Testing
import Foundation
@testable import CreatureSpine

@Test func captureFromGAIAStars() {
    let stars = [
        GAIAStar(
            sourceID: "1234567890",
            ra: 45.0, dec: 30.0,
            parallax: 10.0,
            properMotionRA: 0.1,
            properMotionDEC: -0.05
        )
    ]
    let key = ConstellationKey.capture(visibleStars: stars)

    #expect(key.starCount == 1)
    #expect(!key.regionHash.isEmpty)
    #expect(key.visibleStars[0].sourceID == "1234567890")
}

@Test func deterministicCapture() {
    let stars = [
        GAIAStar(sourceID: "1", ra: 0, dec: 0, parallax: 0, properMotionRA: 0, properMotionDEC: 0),
        GAIAStar(sourceID: "2", ra: 10, dec: 20, parallax: 5, properMotionRA: 0.1, properMotionDEC: -0.1)
    ]
    let date = Date(timeIntervalSince1970: 1000000)
    let key1 = ConstellationKey.capture(visibleStars: stars, at: date)
    let key2 = ConstellationKey.capture(visibleStars: stars, at: date)

    #expect(key1.regionHash == key2.regionHash)
}

@Test func orderIndependentHash() {
    let starA = GAIAStar(sourceID: "AAA", ra: 10, dec: 20, parallax: 1, properMotionRA: 0, properMotionDEC: 0)
    let starB = GAIAStar(sourceID: "BBB", ra: 30, dec: 40, parallax: 2, properMotionRA: 0, properMotionDEC: 0)
    let date = Date(timeIntervalSince1970: 1000000)

    let key1 = ConstellationKey.capture(visibleStars: [starA, starB], at: date)
    let key2 = ConstellationKey.capture(visibleStars: [starB, starA], at: date)

    // Star IDs are sorted before hashing → order-independent
    #expect(key1.regionHash == key2.regionHash)
}

@Test func differentStarsDifferentHash() {
    let starsA = [GAIAStar(sourceID: "1", ra: 0, dec: 0, parallax: 0, properMotionRA: 0, properMotionDEC: 0)]
    let starsB = [GAIAStar(sourceID: "2", ra: 0, dec: 0, parallax: 0, properMotionRA: 0, properMotionDEC: 0)]
    let date = Date(timeIntervalSince1970: 1000000)

    let key1 = ConstellationKey.capture(visibleStars: starsA, at: date)
    let key2 = ConstellationKey.capture(visibleStars: starsB, at: date)

    #expect(key1.regionHash != key2.regionHash)
}

@Test func deriveKeyProduces32Bytes() {
    let stars = [
        GAIAStar(sourceID: "1", ra: 0, dec: 0, parallax: 0, properMotionRA: 0, properMotionDEC: 0)
    ]
    let key = ConstellationKey.capture(visibleStars: stars)
    let derived = key.deriveKey()

    #expect(derived.count == 32)
}

@Test func deriveKeyDeterministic() {
    let stars = [
        GAIAStar(sourceID: "1", ra: 0, dec: 0, parallax: 0, properMotionRA: 0, properMotionDEC: 0)
    ]
    let date = Date(timeIntervalSince1970: 5000)
    let key = ConstellationKey.capture(visibleStars: stars, at: date)

    let derived1 = key.deriveKey()
    let derived2 = key.deriveKey()
    #expect(derived1 == derived2)
}

@Test func emptyStarsCaptureSucceeds() {
    let key = ConstellationKey.capture(visibleStars: [])
    #expect(key.starCount == 0)
    #expect(!key.regionHash.isEmpty)
}

@Test func gaiaStarCodable() throws {
    let star = GAIAStar(
        sourceID: "123456",
        ra: 45.123, dec: -30.456,
        parallax: 2.5,
        properMotionRA: 0.01,
        properMotionDEC: -0.02
    )
    let data = try JSONEncoder().encode(star)
    let decoded = try JSONDecoder().decode(GAIAStar.self, from: data)

    #expect(decoded.sourceID == star.sourceID)
    #expect(decoded.ra == star.ra)
    #expect(decoded.dec == star.dec)
}

@Test func constellationKeyCodable() throws {
    let stars = [
        GAIAStar(sourceID: "1", ra: 10, dec: 20, parallax: 1, properMotionRA: 0, properMotionDEC: 0)
    ]
    let key = ConstellationKey.capture(visibleStars: stars, at: Date(timeIntervalSince1970: 1000))

    let data = try JSONEncoder().encode(key)
    let decoded = try JSONDecoder().decode(ConstellationKey.self, from: data)

    #expect(decoded.regionHash == key.regionHash)
    #expect(decoded.starCount == key.starCount)
}
