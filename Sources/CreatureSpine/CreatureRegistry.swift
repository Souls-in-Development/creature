import Foundation

// MARK: - Spawn Condition

/// Conditions that must be met before a creature type can be spawned at a coordinate.
public enum SpawnCondition: Sendable {
    case always
    case minimumDensity(Float)
    case minimumEnergy(Float)
    case all([SpawnCondition])
    case any([SpawnCondition])

    public func isSatisfied(density: Float, energy: Float) -> Bool {
        switch self {
        case .always:
            return true
        case .minimumDensity(let threshold):
            return density >= threshold
        case .minimumEnergy(let threshold):
            return energy >= threshold
        case .all(let conditions):
            return conditions.allSatisfy { $0.isSatisfied(density: density, energy: energy) }
        case .any(let conditions):
            return conditions.contains { $0.isSatisfied(density: density, energy: energy) }
        }
    }
}

// MARK: - Creature Spec

/// Blueprint for a creature type. Defines what it looks like and when it spawns.
public struct CreatureSpec: Sendable {
    public let name: String
    public let marking: CreatureMarking
    public let defaultPersonality: CreaturePersonality
    public let spawnCondition: SpawnCondition

    public init(
        name: String,
        marking: CreatureMarking,
        defaultPersonality: CreaturePersonality,
        spawnCondition: SpawnCondition
    ) {
        self.name = name
        self.marking = marking
        self.defaultPersonality = defaultPersonality
        self.spawnCondition = spawnCondition
    }
}

// MARK: - Creature Registry

/// Registry of known creature types.
public struct CreatureRegistry: Sendable {
    private var specs: [String: CreatureSpec] = [:]

    public init() {}

    public mutating func register(_ spec: CreatureSpec) {
        specs[spec.name] = spec
    }

    public func spec(named name: String) -> CreatureSpec? {
        specs[name]
    }

    public var allSpecs: [CreatureSpec] {
        Array(specs.values)
    }

    public var count: Int {
        specs.count
    }

    public func spawnableSpecs(density: Float, energy: Float) -> [CreatureSpec] {
        specs.values.filter { $0.spawnCondition.isSatisfied(density: density, energy: energy) }
    }
}
