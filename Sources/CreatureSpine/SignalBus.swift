import Foundation

/// The subconscious IS the signal bus.
/// Transport only. No storage. No learning. Reactive.
///
/// Creatures emit feelings via `pulse()`. Conscious steers creatures via `steer()`.
/// Wave interference resolves at each coordinate before signals reach conscious.
public actor SpineSignalBus {
    private var resolver = WaveResolver()
    private var steeringBuffer: [Feeling] = []
    private var listeners: [UUID: AsyncStream<ResolvedSignal>.Continuation] = [:]

    public init() {}

    // MARK: - Creature → Conscious (upward)

    /// Broadcast a feeling from a creature. Accumulates in the wave resolver.
    public func pulse(_ feeling: Feeling) {
        resolver.add(feeling)
    }

    /// Resolve all accumulated feelings via wave interference.
    /// Returns one ResolvedSignal per active coordinate.
    /// Clears the buffer after resolving.
    public func resolveAll() -> [ResolvedSignal] {
        let coords = resolver.activeCoordinates
        let results = coords.map { resolver.resolve(at: $0) }
        resolver.clear()
        return results
    }

    /// Resolve and push results to all listeners, then clear.
    public func flush() {
        let signals = resolveAll()
        for signal in signals {
            for continuation in listeners.values {
                continuation.yield(signal)
            }
        }
    }

    /// Subscribe to resolved signals (conscious reads these).
    public func listen() -> AsyncStream<ResolvedSignal> {
        let id = UUID()
        return AsyncStream { continuation in
            self.listeners[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeListener(id) }
            }
        }
    }

    // MARK: - Conscious → Creature (downward)

    /// Send a steering feeling from the conscious layer to creatures.
    public func steer(_ feeling: Feeling) {
        steeringBuffer.append(feeling)
    }

    /// Drain steering commands (creatures read these).
    public func drainSteering() -> [Feeling] {
        let steers = steeringBuffer
        steeringBuffer.removeAll()
        return steers
    }

    // MARK: - Private

    private func removeListener(_ id: UUID) {
        listeners.removeValue(forKey: id)
    }
}
