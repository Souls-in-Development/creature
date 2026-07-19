import Foundation

/// Mixes multiple ColourTracks using energy-weighted circular mean for hue
/// and coherence-based saturation. Different hues desaturate toward white
/// (overload). Same hues reinforce (high saturation).
public struct AdditiveMixer: Sendable {
    private var tracks: [ColourTrack] = []

    public init() {}

    /// Add a track to the mix. Zero-energy tracks are accepted but have no weight.
    public mutating func add(_ track: ColourTrack) {
        tracks.append(track)
    }

    /// Number of tracks in the mixer.
    public var count: Int { tracks.count }

    /// Clear all tracks.
    public mutating func reset() {
        tracks.removeAll()
    }

    /// Mix all added tracks into a single ColourTrack.
    /// Returns nil if no tracks were added.
    /// Uses energy-weighted circular mean for hue.
    /// Saturation derived from hue coherence (vector resultant length).
    /// Value is power-mean of input values weighted by energy.
    public func mix() -> ColourTrack? {
        guard !tracks.isEmpty else { return nil }
        if tracks.count == 1 { return tracks[0] }

        // Energy weight for each track: saturation * value
        var cosSum: Float = 0
        var sinSum: Float = 0
        var totalWeight: Float = 0
        var valuePowerSum: Float = 0
        var bestMarking = tracks[0].creatureMarking
        var bestWeight: Float = 0

        for track in tracks {
            let weight = track.saturation * track.value
            guard weight > 1e-6 else { continue }

            let hueRad = track.hue * Float.pi / 180.0
            cosSum += cos(hueRad) * weight
            sinSum += sin(hueRad) * weight
            totalWeight += weight

            // Power-mean (p=2) for value
            valuePowerSum += track.value * track.value * weight

            // Track dominant marking by weight
            if weight > bestWeight {
                bestWeight = weight
                bestMarking = track.creatureMarking
            }
        }

        // If all tracks had zero energy, return first track as-is
        guard totalWeight > 1e-6 else { return tracks[0] }

        // Circular mean hue
        var hue = atan2(sinSum, cosSum) * 180.0 / Float.pi
        if hue < 0 { hue += 360.0 }

        // Coherence = resultant vector length / total weight
        // 1.0 = all same hue, 0.0 = perfectly balanced opposing hues
        let resultantLength = sqrt(cosSum * cosSum + sinSum * sinSum)
        let coherence = resultantLength / totalWeight

        // Saturation = coherence × average input saturation
        let avgSat = tracks.reduce(Float(0)) { $0 + $1.saturation } / Float(tracks.count)
        let saturation = min(1.0, coherence * avgSat)

        // Value = power-mean(p=2) — bright inputs stay bright
        let valuePowerMean = sqrt(valuePowerSum / totalWeight)
        // Boost value when incoherent (approaching white)
        let value = min(1.0, valuePowerMean + (1.0 - coherence) * 0.3)

        return ColourTrack(
            coordinate: tracks[0].coordinate,
            hue: hue,
            saturation: saturation,
            value: value,
            creatureMarking: bestMarking
        )
    }
}
