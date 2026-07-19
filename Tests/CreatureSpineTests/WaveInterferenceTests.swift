import Testing
@testable import CreatureSpine

@Test func singleFeelingPassesThrough() {
    var resolver = WaveResolver()
    let coord = SpineCoordinate(ra: 45, dec: 30, alt: 5)
    let f = Feeling(kind: .warmth, intensity: 0.8, source: CreatureID(), coordinate: coord)
    resolver.add(f)
    let result = resolver.resolve(at: coord)
    #expect(abs(result.vector[.warmth] - 0.8) < 0.001)
    #expect(!result.isTense)
}

@Test func constructiveInterference() {
    var resolver = WaveResolver()
    let coord = SpineCoordinate(ra: 45, dec: 30, alt: 5)
    for _ in 0..<3 {
        resolver.add(Feeling(kind: .warmth, intensity: 0.5, source: CreatureID(), coordinate: coord))
    }
    let result = resolver.resolve(at: coord)
    #expect(result.vector[.warmth] > 1.0) // Constructive addition
    #expect(!result.isTense) // All same direction = no tension
}

@Test func conflictingFeelingsCreateTension() {
    var resolver = WaveResolver()
    let coord = SpineCoordinate(ra: 45, dec: 30, alt: 5)
    resolver.add(Feeling(kind: .warmth, intensity: 0.9, source: CreatureID(), coordinate: coord))
    resolver.add(Feeling(kind: .unease, intensity: 0.8, source: CreatureID(), coordinate: coord))
    let result = resolver.resolve(at: coord)
    #expect(result.isTense) // Opposing signals = tension
    #expect(result.creatureCount == 2)
}

@Test func emptyResolverGivesZero() {
    let resolver = WaveResolver()
    let coord = SpineCoordinate(ra: 45, dec: 30, alt: 5)
    let result = resolver.resolve(at: coord)
    #expect(result.vector.magnitude < 0.001)
    #expect(result.creatureCount == 0)
}

@Test func resolverClearsAfterResolve() {
    var resolver = WaveResolver()
    let coord = SpineCoordinate(ra: 45, dec: 30, alt: 5)
    resolver.add(Feeling(kind: .warmth, intensity: 0.5, source: CreatureID(), coordinate: coord))
    _ = resolver.resolve(at: coord)
    resolver.clear()
    let result = resolver.resolve(at: coord)
    #expect(result.vector.magnitude < 0.001)
}
