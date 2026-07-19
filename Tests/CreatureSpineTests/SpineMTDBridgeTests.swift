import Testing
@testable import CreatureSpine

/// Mock activation target for testing.
final class MockActivationTarget: MTDActivationTarget, @unchecked Sendable {
    var activations: [(ra: Float, dec: Float, radius: Float, strength: Float, pixel: SIMD4<Float>)] = []

    func enqueueColourActivation(ra: Float, dec: Float, radius: Float, strength: Float, pixel: SIMD4<Float>) {
        activations.append((ra, dec, radius, strength, pixel))
    }
}

@Test func flushEmitsActivationsForDirtyCoordinates() {
    let accumulator = TrailAccumulator()
    let target = MockActivationTarget()
    let bridge = SpineMTDBridge(accumulator: accumulator, target: target)

    let coord = SpineCoordinate(ra: 45.0, dec: 30.0, alt: 3)
    accumulator.record(ColourTrack.fromReaction(
        coordinate: coord,
        daemonKeyHue: 120.0,
        reactionIntensity: 0.8,
        energy: 0.9,
        creatureMarking: CreatureMarking(name: "test", pattern: 1)
    ))

    let count = bridge.flush()
    #expect(count == 1)
    #expect(target.activations.count == 1)
    #expect(abs(target.activations[0].ra - 45.0) < 0.01)
    #expect(abs(target.activations[0].dec - 30.0) < 0.01)
    #expect(target.activations[0].strength > 0)
    #expect(target.activations[0].pixel.x > 0)  // encoded hue
}

@Test func flushWithNoDirtyDataEmitsNothing() {
    let accumulator = TrailAccumulator()
    let target = MockActivationTarget()
    let bridge = SpineMTDBridge(accumulator: accumulator, target: target)

    let count = bridge.flush()
    #expect(count == 0)
    #expect(target.activations.isEmpty)
}

@Test func flushDrainsOnce() {
    let accumulator = TrailAccumulator()
    let target = MockActivationTarget()
    let bridge = SpineMTDBridge(accumulator: accumulator, target: target)

    accumulator.record(ColourTrack.fromReaction(
        coordinate: .origin,
        daemonKeyHue: 60.0,
        reactionIntensity: 0.5,
        energy: 0.7,
        creatureMarking: CreatureMarking(name: "test", pattern: 1)
    ))

    _ = bridge.flush()
    let secondCount = bridge.flush()
    #expect(secondCount == 0)
    #expect(target.activations.count == 1)  // Only first flush emitted
}

@Test func flushMultipleCoordinatesBatched() {
    let accumulator = TrailAccumulator()
    let target = MockActivationTarget()
    let bridge = SpineMTDBridge(accumulator: accumulator, target: target)

    for i in 0..<10 {
        accumulator.record(ColourTrack.fromReaction(
            coordinate: SpineCoordinate(ra: Double(i) * 36.0, dec: 0.0, alt: 1),
            daemonKeyHue: Float(i) * 36.0,
            reactionIntensity: 0.8,
            energy: 0.9,
            creatureMarking: CreatureMarking(name: "c\(i)", pattern: UInt8(i))
        ))
    }

    let count = bridge.flush()
    #expect(count == 10)
    #expect(target.activations.count == 10)
}

@Test func activationRadiusScalesWithDensity() {
    let accumulator = TrailAccumulator()
    let target = MockActivationTarget()
    let bridge = SpineMTDBridge(accumulator: accumulator, target: target)

    let coord = SpineCoordinate(ra: 90.0, dec: 0.0, alt: 5)
    // Record many tracks at same coordinate → high density
    for _ in 0..<20 {
        accumulator.record(ColourTrack.fromReaction(
            coordinate: coord,
            daemonKeyHue: 120.0,
            reactionIntensity: 1.0,
            energy: 1.0,
            creatureMarking: CreatureMarking(name: "test", pattern: 1)
        ))
    }

    _ = bridge.flush()
    let activation = target.activations[0]
    // High density → larger radius
    #expect(activation.radius > 1.0)
}
