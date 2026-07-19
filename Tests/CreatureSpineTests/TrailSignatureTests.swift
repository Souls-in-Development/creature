import Testing
import Foundation
@testable import CreatureSpine

@Test func snapshotFromEmptyAccumulator() {
    let acc = TrailAccumulator()
    let sig = TrailSignature.snapshot(from: acc, daemonKeyHue: 210.0)
    #expect(sig.coordinateCount == 0)
    #expect(sig.dominantHue == nil)
    #expect(sig.totalDensity == 0)
}

@Test func snapshotReflectsAccumulatedTrails() {
    let acc = TrailAccumulator()
    let marking = CreatureMarking(name: "scout", pattern: 0)
    let coord = SpineCoordinate(ra: 45, dec: 30, alt: 5)

    for _ in 0..<10 {
        acc.record(ColourTrack.fromReaction(
            coordinate: coord,
            daemonKeyHue: 210.0,
            reactionIntensity: 0.8,
            energy: 0.9,
            creatureMarking: marking
        ))
    }

    let sig = TrailSignature.snapshot(from: acc, daemonKeyHue: 210.0)
    #expect(sig.coordinateCount == 1)
    #expect(sig.totalDensity > 0)
    #expect(sig.markings.contains(marking))
}

@Test func snapshotHashDeterministic() {
    let acc = TrailAccumulator()
    let marking = CreatureMarking(name: "scout", pattern: 0)
    let coord = SpineCoordinate(ra: 45, dec: 30, alt: 5)

    acc.record(ColourTrack.fromReaction(
        coordinate: coord,
        daemonKeyHue: 210.0,
        reactionIntensity: 0.8,
        energy: 0.9,
        creatureMarking: marking
    ))

    let sig1 = TrailSignature.snapshot(from: acc, daemonKeyHue: 210.0)
    let sig2 = TrailSignature.snapshot(from: acc, daemonKeyHue: 210.0)
    #expect(sig1.snapshotHash == sig2.snapshotHash)
}

@Test func differentTrailsDifferentHashes() {
    let marking = CreatureMarking(name: "scout", pattern: 0)

    let acc1 = TrailAccumulator()
    acc1.record(ColourTrack.fromReaction(
        coordinate: SpineCoordinate(ra: 45, dec: 30, alt: 5),
        daemonKeyHue: 210.0,
        reactionIntensity: 0.8,
        energy: 0.9,
        creatureMarking: marking
    ))

    let acc2 = TrailAccumulator()
    acc2.record(ColourTrack.fromReaction(
        coordinate: SpineCoordinate(ra: 90, dec: -45, alt: 3),
        daemonKeyHue: 30.0,
        reactionIntensity: 0.3,
        energy: 0.4,
        creatureMarking: marking
    ))

    let sig1 = TrailSignature.snapshot(from: acc1, daemonKeyHue: 210.0)
    let sig2 = TrailSignature.snapshot(from: acc2, daemonKeyHue: 30.0)
    #expect(sig1.snapshotHash != sig2.snapshotHash)
}
