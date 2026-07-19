import Foundation

// MARK: - Dirty Entry

/// A coordinate that changed since last drain, with aggregated trail data.
public struct DirtyEntry: Sendable {
    public let coordinate: SpineCoordinate
    public let density: Float
    public let averageHue: Float?
    public let dominantMarking: CreatureMarking?
}

// MARK: - Trail Cell

/// Accumulated trail data at a single coordinate.
struct TrailCell {
    /// Short-term intensity (rapid decay, active steering).
    var intensity: Float = 0
    /// Long-term sediment (slow decay, personality rendering).
    var sediment: Float = 0
    /// Weighted average hue (circular mean).
    var hueSum: Float = 0
    var hueCosSum: Float = 0
    var hueSinSum: Float = 0
    /// Visit count for averaging.
    var visits: Int = 0
    /// Which creature types have visited.
    var markings: Set<CreatureMarking> = []
}

// MARK: - Trail Accumulator

/// Accumulates ColourTracks into a trail-density map.
/// Tracks two timescales: intensity (seconds-minutes) and sediment (hours-days).
/// Thread-safe via actor isolation for non-GPU use; GPU version reads from exported buffer.
public final class TrailAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var cells: [String: TrailCell] = [:]
    private var dirtyKeys: Set<String> = []

    /// Per-decay-tick multiplier for intensity. Default 0.98 ≈ slow fade.
    public let decayFactor: Float

    /// Fraction of intensity that sediments per recording. Default 0.1.
    public let sedimentRate: Float

    public init(decayFactor: Float = 0.98, sedimentRate: Float = 0.1) {
        self.decayFactor = decayFactor
        self.sedimentRate = sedimentRate
    }

    /// Record a creature's colour track at a coordinate.
    public func record(_ track: ColourTrack) {
        let key = track.coordinate.stringKey
        lock.lock()
        defer { lock.unlock() }

        var cell = cells[key, default: TrailCell()]
        let energy = track.saturation * track.value
        cell.intensity += energy
        cell.sediment += energy * sedimentRate
        cell.visits += 1
        cell.markings.insert(track.creatureMarking)

        // Circular mean accumulation for hue
        let hueRad = Double(track.hue) * .pi / 180
        cell.hueCosSum += Float(cos(hueRad)) * energy
        cell.hueSinSum += Float(sin(hueRad)) * energy
        cell.hueSum += energy

        cells[key] = cell
        dirtyKeys.insert(key)
    }

    /// Trail density (intensity + sediment) at a coordinate. 0 if unvisited.
    public func density(at coordinate: SpineCoordinate) -> Float {
        lock.lock()
        defer { lock.unlock() }
        guard let cell = cells[coordinate.stringKey] else { return 0 }
        return cell.intensity + cell.sediment
    }

    /// Average hue at a coordinate (circular mean). nil if unvisited.
    public func averageHue(at coordinate: SpineCoordinate) -> Float? {
        lock.lock()
        defer { lock.unlock() }
        guard let cell = cells[coordinate.stringKey], cell.hueSum > 0 else { return nil }
        let avgCos = cell.hueCosSum / cell.hueSum
        let avgSin = cell.hueSinSum / cell.hueSum
        var hue = Float(atan2(Double(avgSin), Double(avgCos)) * 180 / .pi)
        if hue < 0 { hue += 360 }
        return hue
    }

    /// Apply multiplicative decay to all intensity values. Call periodically.
    public func applyDecay() {
        lock.lock()
        defer { lock.unlock() }
        for key in cells.keys {
            cells[key]?.intensity *= decayFactor
        }
    }

    /// Number of coordinates with any trail data.
    public var coordinateCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return cells.count
    }

    /// All coordinate keys with trail data, for snapshot enumeration.
    public var allKeys: [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(cells.keys)
    }

    /// Density map for snapshot (key → density).
    public func densityMap() -> [String: Float] {
        lock.lock()
        defer { lock.unlock() }
        return cells.mapValues { $0.intensity + $0.sediment }
    }

    /// All creature markings that have left trails.
    public func allMarkings() -> Set<CreatureMarking> {
        lock.lock()
        defer { lock.unlock() }
        var result = Set<CreatureMarking>()
        for cell in cells.values {
            result.formUnion(cell.markings)
        }
        return result
    }

    /// Returns coordinates modified since last drain with their aggregated data.
    /// Clears the dirty set. Thread-safe.
    public func drainDirty() -> [DirtyEntry] {
        lock.lock()
        defer { lock.unlock() }

        var entries: [DirtyEntry] = []
        entries.reserveCapacity(dirtyKeys.count)

        for key in dirtyKeys {
            guard let cell = cells[key] else { continue }

            // Parse coordinate from stringKey
            let parts = key.split(separator: ",")
            guard parts.count == 3,
                  let ra = Double(parts[0]),
                  let dec = Double(parts[1]),
                  let alt = Int(parts[2]) else { continue }

            let coord = SpineCoordinate(ra: ra, dec: dec, alt: alt)
            let density = cell.intensity + cell.sediment

            // Circular mean hue
            var avgHue: Float? = nil
            if cell.hueSum > 0 {
                let avgCos = cell.hueCosSum / cell.hueSum
                let avgSin = cell.hueSinSum / cell.hueSum
                var hue = Float(atan2(Double(avgSin), Double(avgCos)) * 180 / .pi)
                if hue < 0 { hue += 360 }
                avgHue = hue
            }

            // Most-visited marking
            let dominant = cell.markings.max(by: { $0.pattern < $1.pattern })

            entries.append(DirtyEntry(
                coordinate: coord,
                density: density,
                averageHue: avgHue,
                dominantMarking: dominant
            ))
        }

        dirtyKeys.removeAll(keepingCapacity: true)
        return entries
    }
}
