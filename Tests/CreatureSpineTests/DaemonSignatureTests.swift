import Testing
import Foundation
@testable import CreatureSpine

@Test func newSignatureHasZeroPattern() {
    let sig = DaemonSignature()
    #expect(sig.currentPattern == 0)
    #expect(sig.emissionCount == 0)
}

@Test func signatureEvolvesWithEmissions() {
    let sig = DaemonSignature()
    let track1 = ColourTrack.fromReaction(
        coordinate: .origin,
        daemonKeyHue: 120.0,
        reactionIntensity: 0.8,
        energy: 0.9,
        creatureMarking: CreatureMarking(name: "test", pattern: 1)
    )
    sig.emit(track1)
    let pattern1 = sig.currentPattern

    let track2 = ColourTrack.fromReaction(
        coordinate: .origin,
        daemonKeyHue: 240.0,
        reactionIntensity: 0.5,
        energy: 0.7,
        creatureMarking: CreatureMarking(name: "test", pattern: 1)
    )
    sig.emit(track2)
    let pattern2 = sig.currentPattern

    #expect(pattern1 != pattern2)  // Pattern evolved
    #expect(sig.emissionCount == 2)
}

@Test func signatureHashDeterministic() {
    let sig1 = DaemonSignature()
    let sig2 = DaemonSignature()

    let track = ColourTrack.fromReaction(
        coordinate: .origin,
        daemonKeyHue: 120.0,
        reactionIntensity: 0.8,
        energy: 0.9,
        creatureMarking: CreatureMarking(name: "test", pattern: 1)
    )

    sig1.emit(track)
    sig2.emit(track)

    #expect(sig1.signatureHash == sig2.signatureHash)
}

@Test func differentEmissionsDifferentHash() {
    let sig1 = DaemonSignature()
    let sig2 = DaemonSignature()

    sig1.emit(ColourTrack.fromReaction(
        coordinate: .origin,
        daemonKeyHue: 120.0,
        reactionIntensity: 0.8, energy: 0.9,
        creatureMarking: CreatureMarking(name: "a", pattern: 1)
    ))
    sig2.emit(ColourTrack.fromReaction(
        coordinate: .origin,
        daemonKeyHue: 240.0,
        reactionIntensity: 0.3, energy: 0.5,
        creatureMarking: CreatureMarking(name: "b", pattern: 2)
    ))

    #expect(sig1.signatureHash != sig2.signatureHash)
}

@Test func emissionOrderMatters() {
    let sig1 = DaemonSignature()
    let sig2 = DaemonSignature()

    let trackA = ColourTrack.fromReaction(
        coordinate: .origin,
        daemonKeyHue: 60.0,
        reactionIntensity: 0.5, energy: 0.7,
        creatureMarking: CreatureMarking(name: "a", pattern: 1)
    )
    let trackB = ColourTrack.fromReaction(
        coordinate: .origin,
        daemonKeyHue: 300.0,
        reactionIntensity: 0.9, energy: 0.4,
        creatureMarking: CreatureMarking(name: "b", pattern: 2)
    )

    sig1.emit(trackA)
    sig1.emit(trackB)

    sig2.emit(trackB)
    sig2.emit(trackA)

    // Different emission order → different hash (can't reproduce by reordering)
    #expect(sig1.signatureHash != sig2.signatureHash)
}

@Test func recentEmissionsLimited() {
    let sig = DaemonSignature()
    for i in 0..<20 {
        sig.emit(ColourTrack.fromReaction(
            coordinate: SpineCoordinate(ra: Double(i), dec: 0, alt: 0),
            daemonKeyHue: Float(i) * 18.0,
            reactionIntensity: 0.5, energy: 0.5,
            creatureMarking: CreatureMarking(name: "test", pattern: 1)
        ))
    }
    let recent = sig.recentEmissions(count: 5)
    #expect(recent.count == 5)
}

@Test func signatureHashNonEmpty() {
    let sig = DaemonSignature()
    sig.emit(ColourTrack.fromReaction(
        coordinate: .origin,
        daemonKeyHue: 90.0,
        reactionIntensity: 1.0, energy: 1.0,
        creatureMarking: CreatureMarking(name: "test", pattern: 1)
    ))
    #expect(sig.signatureHash.count == 64)  // SHA-256 hex = 64 chars
}

@Test func emptySignatureHash() {
    let sig = DaemonSignature()
    let hash = sig.signatureHash
    #expect(hash.count == 64)  // Still valid hash of empty data
}
