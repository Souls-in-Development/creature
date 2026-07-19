import Testing
@testable import CreatureSpine

@Test func signalBusPulseDelivers() async {
    let bus = SpineSignalBus()
    let coord = SpineCoordinate(ra: 45, dec: 30, alt: 5)
    let feeling = Feeling(kind: .novelty, intensity: 0.7, source: CreatureID(), coordinate: coord)

    await bus.pulse(feeling)

    let signals = await bus.resolveAll()
    #expect(signals.count == 1)
    #expect(signals[0].vector[.novelty] > 0.5)
}

@Test func signalBusMultiplePulsesSameCoordinate() async {
    let bus = SpineSignalBus()
    let coord = SpineCoordinate(ra: 45, dec: 30, alt: 5)

    await bus.pulse(Feeling(kind: .warmth, intensity: 0.5, source: CreatureID(), coordinate: coord))
    await bus.pulse(Feeling(kind: .warmth, intensity: 0.3, source: CreatureID(), coordinate: coord))

    let signals = await bus.resolveAll()
    #expect(signals.count == 1)
    #expect(abs(signals[0].vector[.warmth] - 0.8) < 0.001) // Constructive
}

@Test func signalBusSteerReachesCreatures() async {
    let bus = SpineSignalBus()
    let coord = SpineCoordinate(ra: 45, dec: 30, alt: 5)
    let steering = Feeling(kind: .pull, intensity: 0.9, source: CreatureID(), coordinate: coord)

    await bus.steer(steering)

    let steers = await bus.drainSteering()
    #expect(steers.count == 1)
    #expect(steers[0].kind == .pull)
}

@Test func signalBusResolveClearsBuffer() async {
    let bus = SpineSignalBus()
    let coord = SpineCoordinate(ra: 45, dec: 30, alt: 5)
    await bus.pulse(Feeling(kind: .warmth, intensity: 0.5, source: CreatureID(), coordinate: coord))

    _ = await bus.resolveAll()
    let signals = await bus.resolveAll()
    #expect(signals.isEmpty) // Buffer cleared after resolve
}

@Test func signalBusListenStream() async {
    let bus = SpineSignalBus()
    let coord = SpineCoordinate(ra: 45, dec: 30, alt: 5)

    // Get the stream before sending
    let stream = await bus.listen()

    // Send a pulse
    await bus.pulse(Feeling(kind: .spark, intensity: 0.9, source: CreatureID(), coordinate: coord))
    await bus.flush()

    // Read one resolved signal from the stream
    var received: ResolvedSignal?
    for await signal in stream {
        received = signal
        break
    }
    #expect(received != nil)
    #expect(received?.vector[.spark] ?? 0 > 0.5)
}
