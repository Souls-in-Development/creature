import Foundation

/// Tunable personality parameters. Set by the conscious layer, read by creatures.
/// These are NOT learned — they are adjusted externally.
public struct CreaturePersonality: Sendable {
    /// Desire to explore unknown coordinates. 0 = avoidant, 1 = maximally curious.
    public var curiosity: Float
    /// Willingness to cross high-activation-energy gates. 0 = timid, 1 = reckless.
    public var boldness: Float
    /// Exploration width. 0 = depth-first, 1 = breadth-first.
    public var breadth: Float
    /// How long to stay in a region before moving on. 0 = flighty, 1 = stubborn.
    public var persistence: Float

    public init(
        curiosity: Float = 0.5,
        boldness: Float = 0.5,
        breadth: Float = 0.5,
        persistence: Float = 0.5
    ) {
        self.curiosity = curiosity
        self.boldness = boldness
        self.breadth = breadth
        self.persistence = persistence
    }
}

/// A stimulus that a creature reacts to at a coordinate.
public struct Stimulus: Sendable {
    public let strength: Float
    public let coordinate: SpineCoordinate

    public init(strength: Float, coordinate: SpineCoordinate) {
        self.strength = strength.clamped(to: 0...1)
        self.coordinate = coordinate
    }
}

/// Conscious layer's adjustments to creature personality.
public enum ConsciousAdjustment: Sendable {
    case setCuriosity(Float)
    case setBoldness(Float)
    case setBreadth(Float)
    case setPersistence(Float)
}

/// Topology constraints from the unconscious layer.
public enum TopologyConstraint: Sendable {
    /// Crossing an activation energy gate costs energy.
    case energyGate(cost: Float)
    /// Constrain movement to a path between two points.
    case link(from: SpineCoordinate, to: SpineCoordinate)
    /// Restrict to a coordinate region.
    case regionBound(center: SpineCoordinate, radius: Double)
}
