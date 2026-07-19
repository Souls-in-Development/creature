import Testing
import Foundation
@testable import CreatureSpine

/// A simple creature for integration testing.
struct IntegrationCreature: Creature {
    let id: CreatureID
    let marking = CreatureMarking(name: "integration", pattern: 1)
    var position: SpineCoordinate
    var energy: Float
    var personality: CreaturePersonality

    func react(to stimulus: Stimulus, daemonKeyHue: Float) -> (Feeling, ColourTrack) {
        let feelingKind: FeelingKind = stimulus.strength > 0.5 ? .warmth : .novelty
        let feeling = Feeling(
            kind: feelingKind,
            intensity: stimulus.strength * personality.curiosity,
            source: id,
            coordinate: position
        )
        let track = ColourTrack.fromReaction(
            coordinate: position,
            daemonKeyHue: daemonKeyHue,
            reactionIntensity: stimulus.strength,
            energy: energy,
            creatureMarking: marking
        )
        return (feeling, track)
    }

    mutating func tune(_ adjustment: ConsciousAdjustment) {
        switch adjustment {
        case .setCuriosity(let v): personality.curiosity = v
        case .setBoldness(let v): personality.boldness = v
        case .setBreadth(let v): personality.breadth = v
        case .setPersistence(let v): personality.persistence = v
        }
    }

    mutating func constrain(_ topology: TopologyConstraint) {
        if case .energyGate(let cost) = topology {
            energy = max(0, energy - cost)
        }
    }
}

@Test func fullCreatureLifecycle() async {
    let bus = SpineSignalBus()
    let accumulator = TrailAccumulator()
    let daemonHue: Float = 210.0

    // 1. Spawn a creature at a coordinate
    let coord = SpineCoordinate(ra: 45, dec: 30, alt: 5)
    var creature = IntegrationCreature(
        id: CreatureID(),
        position: coord,
        energy: 1.0,
        personality: CreaturePersonality(curiosity: 0.8)
    )

    // 2. Creature reacts to a stimulus
    let stimulus = Stimulus(strength: 0.7, coordinate: coord)
    let (feeling, track) = creature.react(to: stimulus, daemonKeyHue: daemonHue)

    // 3. Feeling goes through signal bus (creature → conscious)
    await bus.pulse(feeling)
    let resolved = await bus.resolveAll()
    #expect(resolved.count == 1)
    #expect(resolved[0].vector[.warmth] > 0) // strength 0.7 > 0.5 → warmth

    // 4. Colour track accumulates (byproduct)
    accumulator.record(track)
    let density = accumulator.density(at: coord)
    #expect(density > 0)

    // 5. Trail snapshot captures the state
    let sig = TrailSignature.snapshot(from: accumulator, daemonKeyHue: daemonHue)
    #expect(sig.coordinateCount == 1)
    #expect(sig.totalDensity > 0)

    // Suppress unused variable warning
    _ = creature
}

@Test func multipleCreatureWaveInterference() async {
    let bus = SpineSignalBus()
    let coord = SpineCoordinate(ra: 45, dec: 30, alt: 5)

    // 3 creatures all feel warmth at same coordinate → constructive interference
    for _ in 0..<3 {
        let creature = IntegrationCreature(
            id: CreatureID(),
            position: coord,
            energy: 1.0,
            personality: CreaturePersonality(curiosity: 0.8)
        )
        let (feeling, _) = creature.react(
            to: Stimulus(strength: 0.9, coordinate: coord),
            daemonKeyHue: 210.0
        )
        await bus.pulse(feeling)
    }

    let resolved = await bus.resolveAll()
    #expect(resolved.count == 1)
    #expect(resolved[0].vector[.warmth] > 1.5) // 3 × ~0.72 constructive
    #expect(!resolved[0].isTense) // All same direction
}

@Test func consciousSteersCreature() async {
    let bus = SpineSignalBus()

    // Conscious sends steering via bus
    let steerCoord = SpineCoordinate(ra: 90, dec: 60, alt: 3)
    await bus.steer(Feeling(kind: .pull, intensity: 0.9, source: CreatureID(), coordinate: steerCoord))

    // Creature reads steering
    let steers = await bus.drainSteering()
    #expect(steers.count == 1)
    #expect(steers[0].kind == .pull)
    #expect(steers[0].coordinate == steerCoord)

    // Creature adjusts based on steering
    var creature = IntegrationCreature(
        id: CreatureID(),
        position: SpineCoordinate(ra: 45, dec: 30, alt: 5),
        energy: 1.0,
        personality: CreaturePersonality()
    )
    creature.tune(.setCuriosity(0.9)) // Conscious increases curiosity
    #expect(abs(creature.personality.curiosity - 0.9) < 0.001)
}

@Test func trailDecayOverTime() {
    let acc = TrailAccumulator(decayFactor: 0.5)
    let marking = CreatureMarking(name: "test", pattern: 0)
    let coord = SpineCoordinate(ra: 45, dec: 30, alt: 5)

    // Record a track
    acc.record(ColourTrack.fromReaction(
        coordinate: coord, daemonKeyHue: 210.0,
        reactionIntensity: 1.0, energy: 1.0, creatureMarking: marking
    ))

    let initial = acc.density(at: coord)

    // Apply decay 5 times
    for _ in 0..<5 { acc.applyDecay() }
    let decayed = acc.density(at: coord)

    // Intensity decayed but sediment remains
    #expect(decayed < initial)
    #expect(decayed > 0) // Sediment preserves some density
}
