import Testing
@testable import CreatureSpine

// MARK: - Test creature conforming to protocol

struct ScoutCreature: Creature {
    let id: CreatureID
    let marking = CreatureMarking(name: "scout", pattern: 0)
    var position: SpineCoordinate
    var energy: Float
    var personality: CreaturePersonality

    func react(to stimulus: Stimulus, daemonKeyHue: Float) -> (Feeling, ColourTrack) {
        let feeling = Feeling(
            kind: .novelty,
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
            energy -= cost
            energy = max(0, energy)
        }
    }
}

@Test func creatureReactsWithFeelingAndTrack() {
    let creature = ScoutCreature(
        id: CreatureID(),
        position: SpineCoordinate(ra: 45, dec: 30, alt: 5),
        energy: 1.0,
        personality: CreaturePersonality()
    )
    let stimulus = Stimulus(strength: 0.8, coordinate: creature.position)
    let (feeling, track) = creature.react(to: stimulus, daemonKeyHue: 210.0)

    #expect(feeling.kind == .novelty)
    #expect(feeling.intensity > 0)
    #expect(track.coordinate == creature.position)
    #expect(abs(track.hue - 210.0) < 0.001)
}

@Test func creatureTuning() {
    var creature = ScoutCreature(
        id: CreatureID(),
        position: .origin,
        energy: 1.0,
        personality: CreaturePersonality()
    )
    #expect(creature.personality.curiosity == 0.5)
    creature.tune(.setCuriosity(0.9))
    #expect(abs(creature.personality.curiosity - 0.9) < 0.001)
}

@Test func creatureEnergyGateConstraint() {
    var creature = ScoutCreature(
        id: CreatureID(),
        position: .origin,
        energy: 0.6,
        personality: CreaturePersonality()
    )
    creature.constrain(.energyGate(cost: 0.4))
    #expect(abs(creature.energy - 0.2) < 0.001)

    creature.constrain(.energyGate(cost: 0.5))
    #expect(creature.energy == 0)
}

@Test func personalityDefaults() {
    let p = CreaturePersonality()
    #expect(p.curiosity == 0.5)
    #expect(p.boldness == 0.5)
    #expect(p.breadth == 0.5)
    #expect(p.persistence == 0.5)
}
