import Testing
@testable import CreatureSpine

@Test func registryDefaultCreatureTypes() {
    let registry = CreatureRegistry()
    #expect(registry.count == 0)
}

@Test func registerCreatureType() {
    var registry = CreatureRegistry()
    let spec = CreatureSpec(
        name: "scout",
        marking: CreatureMarking(name: "scout", pattern: 0),
        defaultPersonality: CreaturePersonality(curiosity: 0.8, boldness: 0.6),
        spawnCondition: .minimumDensity(0.15)
    )
    registry.register(spec)
    #expect(registry.count == 1)
    #expect(registry.spec(named: "scout") != nil)
}

@Test func spawnConditionMinimumDensity() {
    let condition = SpawnCondition.minimumDensity(0.15)
    #expect(condition.isSatisfied(density: 0.2, energy: 1.0))
    #expect(!condition.isSatisfied(density: 0.1, energy: 1.0))
}

@Test func spawnConditionMinimumEnergy() {
    let condition = SpawnCondition.minimumEnergy(0.5)
    #expect(condition.isSatisfied(density: 0.0, energy: 0.6))
    #expect(!condition.isSatisfied(density: 0.0, energy: 0.3))
}

@Test func spawnConditionCombined() {
    let condition = SpawnCondition.all([
        .minimumDensity(0.1),
        .minimumEnergy(0.3)
    ])
    #expect(condition.isSatisfied(density: 0.2, energy: 0.5))
    #expect(!condition.isSatisfied(density: 0.2, energy: 0.1))
    #expect(!condition.isSatisfied(density: 0.05, energy: 0.5))
}

@Test func registryLookupByName() {
    var registry = CreatureRegistry()
    let scout = CreatureSpec(
        name: "scout",
        marking: CreatureMarking(name: "scout", pattern: 0),
        defaultPersonality: CreaturePersonality(curiosity: 0.8),
        spawnCondition: .minimumDensity(0.15)
    )
    let forager = CreatureSpec(
        name: "forager",
        marking: CreatureMarking(name: "forager", pattern: 1),
        defaultPersonality: CreaturePersonality(boldness: 0.7),
        spawnCondition: .minimumEnergy(0.3)
    )
    registry.register(scout)
    registry.register(forager)

    #expect(registry.spec(named: "scout")?.marking.pattern == 0)
    #expect(registry.spec(named: "forager")?.marking.pattern == 1)
    #expect(registry.spec(named: "nonexistent") == nil)
}

@Test func registryAllSpecs() {
    var registry = CreatureRegistry()
    registry.register(CreatureSpec(
        name: "a",
        marking: CreatureMarking(name: "a", pattern: 0),
        defaultPersonality: CreaturePersonality(),
        spawnCondition: .always
    ))
    registry.register(CreatureSpec(
        name: "b",
        marking: CreatureMarking(name: "b", pattern: 1),
        defaultPersonality: CreaturePersonality(),
        spawnCondition: .always
    ))
    #expect(registry.allSpecs.count == 2)
}
