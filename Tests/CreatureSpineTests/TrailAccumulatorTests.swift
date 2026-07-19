import Testing
@testable import CreatureSpine

@Test func accumulatorRecordsTrack() {
    let acc = TrailAccumulator()
    let marking = CreatureMarking(name: "scout", pattern: 0)
    let track = ColourTrack.fromReaction(
        coordinate: SpineCoordinate(ra: 45, dec: 30, alt: 5),
        daemonKeyHue: 210.0,
        reactionIntensity: 0.8,
        energy: 0.9,
        creatureMarking: marking
    )
    acc.record(track)

    let density = acc.density(at: SpineCoordinate(ra: 45, dec: 30, alt: 5))
    #expect(density > 0)
}

@Test func accumulatorDecay() {
    let acc = TrailAccumulator(decayFactor: 0.5)
    let coord = SpineCoordinate(ra: 45, dec: 30, alt: 5)
    let marking = CreatureMarking(name: "scout", pattern: 0)
    let track = ColourTrack.fromReaction(
        coordinate: coord,
        daemonKeyHue: 210.0,
        reactionIntensity: 1.0,
        energy: 1.0,
        creatureMarking: marking
    )
    acc.record(track)
    let before = acc.density(at: coord)
    acc.applyDecay()
    let after = acc.density(at: coord)
    #expect(after < before)
    // density = intensity + sediment. Decay only affects intensity.
    // before = 1.0 (intensity) + 0.1 (sediment) = 1.1
    // after  = 0.5 (intensity*0.5) + 0.1 (sediment) = 0.6
    #expect(after < before)
    #expect(after > 0)
}

@Test func accumulatorEmptyDensityIsZero() {
    let acc = TrailAccumulator()
    let density = acc.density(at: .origin)
    #expect(density == 0)
}

@Test func accumulatorMultipleTracksAccumulate() {
    let acc = TrailAccumulator()
    let coord = SpineCoordinate(ra: 45, dec: 30, alt: 5)
    let marking = CreatureMarking(name: "scout", pattern: 0)
    for _ in 0..<5 {
        acc.record(ColourTrack.fromReaction(
            coordinate: coord,
            daemonKeyHue: 210.0,
            reactionIntensity: 0.5,
            energy: 0.5,
            creatureMarking: marking
        ))
    }
    let density = acc.density(at: coord)
    #expect(density > 1.0) // Multiple visits accumulate
}

@Test func drainDirtyReturnsRecentActivity() {
    let acc = TrailAccumulator()
    let coord = SpineCoordinate(ra: 45.0, dec: 30.0, alt: 3)
    let track = ColourTrack.fromReaction(
        coordinate: coord,
        daemonKeyHue: 120.0,
        reactionIntensity: 0.8,
        energy: 0.9,
        creatureMarking: CreatureMarking(name: "test", pattern: 1)
    )
    acc.record(track)

    let dirty = acc.drainDirty()
    #expect(dirty.count == 1)
    #expect(dirty[0].coordinate == coord)
    #expect(dirty[0].density > 0)
    #expect(dirty[0].averageHue != nil)
}

@Test func drainDirtyClearsAfterDrain() {
    let acc = TrailAccumulator()
    let coord = SpineCoordinate(ra: 45.0, dec: 30.0, alt: 3)
    let track = ColourTrack.fromReaction(
        coordinate: coord,
        daemonKeyHue: 120.0,
        reactionIntensity: 0.8,
        energy: 0.9,
        creatureMarking: CreatureMarking(name: "test", pattern: 1)
    )
    acc.record(track)
    _ = acc.drainDirty()

    let secondDrain = acc.drainDirty()
    #expect(secondDrain.isEmpty)
}

@Test func drainDirtyMultipleCoordinates() {
    let acc = TrailAccumulator()
    let coordA = SpineCoordinate(ra: 10.0, dec: 20.0, alt: 1)
    let coordB = SpineCoordinate(ra: 50.0, dec: -10.0, alt: 2)

    acc.record(ColourTrack.fromReaction(
        coordinate: coordA, daemonKeyHue: 60.0,
        reactionIntensity: 0.5, energy: 0.7,
        creatureMarking: CreatureMarking(name: "a", pattern: 1)
    ))
    acc.record(ColourTrack.fromReaction(
        coordinate: coordB, daemonKeyHue: 200.0,
        reactionIntensity: 0.9, energy: 0.8,
        creatureMarking: CreatureMarking(name: "b", pattern: 2)
    ))

    let dirty = acc.drainDirty()
    #expect(dirty.count == 2)
    let coords = Set(dirty.map { $0.coordinate })
    #expect(coords.contains(coordA))
    #expect(coords.contains(coordB))
}
