// SIMD4 and friends are Swift standard library types; the `simd` module
// itself is Apple-only and not actually needed here.
// Foundation supplies `log2` on every platform; it arrived via `simd` on Apple,
// which is why this file carried no explicit import.
import Foundation
#if canImport(simd)
import simd
#endif

/// Protocol for receiving colour-encoded activations.
/// Implemented by any Metal texture backend.
public protocol MTDActivationTarget: AnyObject, Sendable {
    /// Enqueue a colour activation at a spine coordinate.
    /// - Parameters:
    ///   - ra: Right ascension (0-360)
    ///   - dec: Declination (-90 to +90)
    ///   - radius: Spread radius (scales with density)
    ///   - strength: Activation strength (0-1)
    ///   - pixel: SIMD4<Float> encoded colour (R=hue/360, G=sat, B=val, A=pattern/255)
    func enqueueColourActivation(ra: Float, dec: Float, radius: Float, strength: Float, pixel: SIMD4<Float>)
}

/// Bridges TrailAccumulator to the MTD texture pipeline.
/// On flush, drains dirty coordinates from the accumulator,
/// encodes each via ColourTrackEncoder, and emits activation commands.
public final class SpineMTDBridge: Sendable {
    private let accumulator: TrailAccumulator
    private let target: MTDActivationTarget

    /// Base radius for activation spread (degrees). Scales up with density.
    public let baseRadius: Float

    /// Minimum density threshold to emit an activation.
    public let densityThreshold: Float

    public init(
        accumulator: TrailAccumulator,
        target: MTDActivationTarget,
        baseRadius: Float = 1.0,
        densityThreshold: Float = 0.0
    ) {
        self.accumulator = accumulator
        self.target = target
        self.baseRadius = baseRadius
        self.densityThreshold = densityThreshold
    }

    /// Drain dirty coordinates and emit activations.
    /// Returns the number of activations emitted.
    @discardableResult
    public func flush() -> Int {
        let dirty = accumulator.drainDirty()
        var emitted = 0

        for entry in dirty {
            guard entry.density > densityThreshold else { continue }

            let pixel = ColourTrackEncoder.encodeEntry(entry)
            let strength = min(1.0, entry.density)
            // Radius scales with log of density for diminishing returns
            let radius = baseRadius + log2(1.0 + entry.density)

            target.enqueueColourActivation(
                ra: Float(entry.coordinate.ra),
                dec: Float(entry.coordinate.dec),
                radius: radius,
                strength: strength,
                pixel: pixel
            )
            emitted += 1
        }

        return emitted
    }
}
