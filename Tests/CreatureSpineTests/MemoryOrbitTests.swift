import Testing
import Foundation
@testable import CreatureSpine

@Suite struct MemoryOrbitTests {

    @Test func createMemoryOrbit() {
        let orbit = MemoryOrbit(
            label: "First meeting",
            semiMajorAxis: 0.8,
            eccentricity: 0.3,
            orbitalPeriod: 7.0,
            dimensions: MemoryDimensions(visual: 0.9, auditory: 0.2, emotional: 1.0, somatic: 0.1, semantic: 0.5)
        )
        #expect(orbit.label == "First meeting")
        #expect(orbit.semiMajorAxis == 0.8)
        #expect(orbit.perihelion < orbit.aphelion)
    }

    @Test func perihelionAndAphelion() {
        let orbit = MemoryOrbit(
            label: "test",
            semiMajorAxis: 1.0,
            eccentricity: 0.5,
            orbitalPeriod: 10.0,
            dimensions: MemoryDimensions()
        )
        // perihelion = a * (1 - e) = 1.0 * 0.5 = 0.5
        // aphelion = a * (1 + e) = 1.0 * 1.5 = 1.5
        #expect(abs(orbit.perihelion - 0.5) < 0.001)
        #expect(abs(orbit.aphelion - 1.5) < 0.001)
    }

    @Test func vividnessAtPhase() {
        let orbit = MemoryOrbit(
            label: "test",
            semiMajorAxis: 1.0,
            eccentricity: 0.5,
            orbitalPeriod: 10.0,
            dimensions: MemoryDimensions()
        )
        // At phase 0 (perihelion): most vivid
        let vivid = orbit.vividness(atPhase: 0)
        // At phase π (aphelion): least vivid
        let faded = orbit.vividness(atPhase: .pi)
        #expect(vivid > faded)
        #expect(vivid >= 0 && vivid <= 1)
        #expect(faded >= 0 && faded <= 1)
    }

    @Test func memoryOrbitSystemAddAndQuery() {
        var system = MemoryOrbitSystem()
        system.add(MemoryOrbit(
            label: "First meeting",
            semiMajorAxis: 0.9,
            eccentricity: 0.2,
            orbitalPeriod: 7.0,
            dimensions: MemoryDimensions(visual: 1.0, auditory: 0.5, emotional: 1.0, somatic: 0.0, semantic: 0.3)
        ))
        system.add(MemoryOrbit(
            label: "Learned to code",
            semiMajorAxis: 0.6,
            eccentricity: 0.4,
            orbitalPeriod: 14.0,
            dimensions: MemoryDimensions(visual: 0.2, auditory: 0.0, emotional: 0.5, somatic: 0.8, semantic: 0.9)
        ))
        #expect(system.count == 2)
        #expect(system.orbit(labeled: "First meeting") != nil)
        #expect(system.orbit(labeled: "nonexistent") == nil)
    }

    @Test func currentVividnessSnapshot() {
        var system = MemoryOrbitSystem()
        system.add(MemoryOrbit(
            label: "A", semiMajorAxis: 1.0, eccentricity: 0.0, orbitalPeriod: 1.0,
            dimensions: MemoryDimensions()
        ))
        // With zero eccentricity, vividness should be constant at all phases
        let snapshot = system.vividnessSnapshot(at: Date())
        #expect(snapshot.count == 1)
        #expect(snapshot["A"]! > 0)
    }

    @Test func hashForHumanKey() {
        var system = MemoryOrbitSystem()
        system.add(MemoryOrbit(
            label: "A", semiMajorAxis: 0.5, eccentricity: 0.1, orbitalPeriod: 3.0,
            dimensions: MemoryDimensions(visual: 1, auditory: 0, emotional: 1, somatic: 0, semantic: 0)
        ))
        let hash = system.deriveKey(at: Date(timeIntervalSince1970: 1000))
        #expect(hash.count == 32) // SHA-256 = 32 bytes
    }

    @Test func deterministicHash() {
        var system = MemoryOrbitSystem()
        system.add(MemoryOrbit(
            label: "X", semiMajorAxis: 0.7, eccentricity: 0.3, orbitalPeriod: 5.0,
            dimensions: MemoryDimensions()
        ))
        let date = Date(timeIntervalSince1970: 5000)
        let hash1 = system.deriveKey(at: date)
        let hash2 = system.deriveKey(at: date)
        #expect(hash1 == hash2)
    }

    @Test func memoryOrbitCodable() throws {
        let orbit = MemoryOrbit(
            label: "test", semiMajorAxis: 0.5, eccentricity: 0.2, orbitalPeriod: 7.0,
            dimensions: MemoryDimensions(visual: 0.5, auditory: 0.5, emotional: 0.5, somatic: 0.5, semantic: 0.5)
        )
        let data = try JSONEncoder().encode(orbit)
        let decoded = try JSONDecoder().decode(MemoryOrbit.self, from: data)
        #expect(decoded.label == orbit.label)
        #expect(decoded.semiMajorAxis == orbit.semiMajorAxis)
    }
}
