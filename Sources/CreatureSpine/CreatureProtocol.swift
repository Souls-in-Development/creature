import Foundation

/// A creature: creative but not intelligent. Instinct, not thought.
///
/// - Spawned by the unconscious (deterministic infrastructure).
/// - Lives in the subconscious (signal bus transport).
/// - Emits feelings upward to conscious and receives steering downward.
/// - Leaves colour tracks as a byproduct of reacting — footprints in snow.
/// - Does NOT learn. Does NOT persist. Shaped externally by both ends.
public protocol Creature: Sendable {
    var id: CreatureID { get }
    var marking: CreatureMarking { get }
    var position: SpineCoordinate { get }
    var energy: Float { get }
    var personality: CreaturePersonality { get }

    /// React to a stimulus at current position.
    /// Returns a feeling (signal to conscious) and a colour track (byproduct footprint).
    func react(to stimulus: Stimulus, daemonKeyHue: Float) -> (Feeling, ColourTrack)

    /// Shaped by conscious layer — adjust personality parameters.
    mutating func tune(_ adjustment: ConsciousAdjustment)

    /// Shaped by unconscious layer — apply topological constraints.
    mutating func constrain(_ topology: TopologyConstraint)
}

extension Creature {
    /// Whether this creature has energy to continue reacting.
    public var isAlive: Bool { energy > 0 }
}
