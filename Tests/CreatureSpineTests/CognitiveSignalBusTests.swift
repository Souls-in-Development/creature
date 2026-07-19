//
//  CognitiveSignalBusTests.swift
//  CreatureSpineTests
//
//  Tests for the CognitiveSignalBus with typed payloads.
//

import XCTest
@testable import CreatureSpine

final class CognitiveSignalBusTests: XCTestCase {
    
    // MARK: - Test Receiver
    
    /// Test receiver implementation for unit tests.
    /// `@unchecked Sendable`: handlers are assigned once in test setup before any
    /// concurrent use, matching the pattern used by `WeakCognitiveReceiver` in
    /// CognitiveSignalBus.swift.
    final class TestReceiver: CognitiveReceiver, @unchecked Sendable {
        let receiverName: String
        let interestedSignals: Set<String>

        var whisperHandler: ((CognitiveWhisper) async throws -> [String: AnyCodable]?)?
        var pulseHandler: ((CognitivePulse) async -> Void)?
        
        init(name: String, interestedSignals: Set<String> = []) {
            self.receiverName = name
            self.interestedSignals = interestedSignals
        }
        
        func handleWhisper(_ whisper: CognitiveWhisper) async throws -> [String: AnyCodable]? {
            return try await whisperHandler?(whisper)
        }
        
        func handlePulse(_ pulse: CognitivePulse) async {
            await pulseHandler?(pulse)
        }
    }
    
    // MARK: - Test 1: Register and Whisper
    
    /// Test that a registered receiver can receive whispers and respond
    func testRegisterAndWhisper() async throws {
        let bus = CognitiveSignalBus()
        let receiver = TestReceiver(name: "testReceiver")
        
        // Set up handler to return a response
        receiver.whisperHandler = { whisper in
            return ["response": .string("Hello from \(whisper.targetReceiver)")]
        }
        
        // Register receiver
        await bus.register(receiver)
        
        // Send whisper
        let signal = CognitiveSignal(name: "greeting", payload: ["message": .string("Hello")])
        let whisper = CognitiveWhisper(signal: signal, target: "testReceiver", timeout: 5.0)
        
        let response = try await bus.whisper(whisper)
        
        XCTAssertNotNil(response)
        XCTAssertEqual(response?["response"]?.stringValue, "Hello from testReceiver")
        
        let count = await bus.receiverCount()
        XCTAssertEqual(count, 1)
    }
    
    // MARK: - Test 2: Unknown Receiver Throws
    
    /// Test that whispering to an unknown receiver throws receiverNotFound
    func testUnknownReceiverThrows() async throws {
        let bus = CognitiveSignalBus()
        
        let signal = CognitiveSignal(name: "greeting", payload: ["message": .string("Hello")])
        let whisper = CognitiveWhisper(signal: signal, target: "nonExistentReceiver", timeout: 5.0)
        
        do {
            _ = try await bus.whisper(whisper)
            XCTFail("Expected receiverNotFound error")
        } catch CognitiveSignalError.receiverNotFound(let name) {
            XCTAssertEqual(name, "nonExistentReceiver")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Test 3: Pulse Delivery
    
    /// Test that pulses are delivered to interested receivers
    func testPulseDelivery() async throws {
        let bus = CognitiveSignalBus()
        
        // Create receivers with different interests
        let receiver1 = TestReceiver(name: "receiver1", interestedSignals: ["feeling.update"])
        let receiver2 = TestReceiver(name: "receiver2", interestedSignals: ["trail.mark"])
        let receiver3 = TestReceiver(name: "receiver3", interestedSignals: []) // Interested in all
        
        var receiver1Handled = false
        var receiver2Handled = false
        var receiver3Handled = false
        
        receiver1.pulseHandler = { _ in receiver1Handled = true }
        receiver2.pulseHandler = { _ in receiver2Handled = true }
        receiver3.pulseHandler = { _ in receiver3Handled = true }
        
        await bus.register(receiver1)
        await bus.register(receiver2)
        await bus.register(receiver3)
        
        // Send pulse for "feeling.update" - should reach receiver1 and receiver3
        let signal = CognitiveSignal(name: "feeling.update", payload: ["value": .double(0.8)])
        let pulse = CognitivePulse(signal: signal)
        
        let handledCount = await bus.pulse(pulse)
        
        // Wait a moment for async handlers
        try await Task.sleep(nanoseconds: 100_000_000)
        
        XCTAssertEqual(handledCount, 3) // All receivers get broadcast
        XCTAssertTrue(receiver1Handled)
        XCTAssertTrue(receiver2Handled)
        XCTAssertTrue(receiver3Handled)
    }
    
    // MARK: - Test 4: Dynamic Signal Registration
    
    /// Test that signals can be registered and checked dynamically
    func testDynamicSignalRegistration() async throws {
        let bus = CognitiveSignalBus()
        
        // Initially no signals registered
        var registered = await bus.isSignalRegistered("custom.signal")
        XCTAssertFalse(registered)
        
        // Register signal
        await bus.registerSignal("custom.signal")
        registered = await bus.isSignalRegistered("custom.signal")
        XCTAssertTrue(registered)
        
        // Register multiple signals
        await bus.registerSignal("another.signal")
        await bus.registerSignal("third.signal")
        
        let signals = await bus.registeredSignalsList()
        XCTAssertEqual(signals.count, 3)
        XCTAssertTrue(signals.contains("custom.signal"))
        XCTAssertTrue(signals.contains("another.signal"))
        XCTAssertTrue(signals.contains("third.signal"))
    }
    
    // MARK: - Test 5: Timeout Throws
    
    /// Test that whispers timeout when receiver doesn't respond in time
    func testTimeoutThrows() async throws {
        let bus = CognitiveSignalBus()
        let receiver = TestReceiver(name: "slowReceiver")
        
        // Set up handler that delays beyond timeout
        receiver.whisperHandler = { _ in
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            return ["response": .string("Too late")]
        }
        
        await bus.register(receiver)
        
        let signal = CognitiveSignal(name: "request", payload: [:])
        let whisper = CognitiveWhisper(signal: signal, target: "slowReceiver", timeout: 0.5) // 0.5s timeout
        
        do {
            _ = try await bus.whisper(whisper)
            XCTFail("Expected timeout error")
        } catch CognitiveSignalError.timeout(let message) {
            XCTAssertTrue(message.contains("timed out"))
            XCTAssertTrue(message.contains("slowReceiver"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Test 6: Receiver Count
    
    /// Test that receiver count is accurate including cleanup of nil references
    func testReceiverCount() async throws {
        let bus = CognitiveSignalBus()
        
        // Start with zero
        var count = await bus.receiverCount()
        XCTAssertEqual(count, 0)
        
        // Add receivers
        let receiver1 = TestReceiver(name: "receiver1")
        let receiver2 = TestReceiver(name: "receiver2")
        let receiver3 = TestReceiver(name: "receiver3")
        
        await bus.register(receiver1)
        await bus.register(receiver2)
        await bus.register(receiver3)
        
        count = await bus.receiverCount()
        XCTAssertEqual(count, 3)
        
        // Remove one
        _ = await bus.unregister("receiver2")
        count = await bus.receiverCount()
        XCTAssertEqual(count, 2)
        
        // Remove non-existent
        let removed = await bus.unregister("nonExistent")
        XCTAssertFalse(removed)
        count = await bus.receiverCount()
        XCTAssertEqual(count, 2)
        
        // Remove all
        _ = await bus.unregister("receiver1")
        _ = await bus.unregister("receiver3")
        count = await bus.receiverCount()
        XCTAssertEqual(count, 0)
    }
    
    // MARK: - Additional Edge Cases
    
    /// Test signal creation with different payload types
    func testSignalPayloadTypes() async throws {
        // String payload
        let stringSignal = CognitiveSignal(name: "test", value: "hello")
        XCTAssertEqual(stringSignal.payload["value"]?.stringValue, "hello")
        
        // Double payload
        let doubleSignal = CognitiveSignal(name: "test", value: 3.14)
        XCTAssertEqual(doubleSignal.payload["value"]?.doubleValue, 3.14)
        
        // Complex payload
        let complexSignal = CognitiveSignal(
            name: "complex",
            payload: [
                "string": .string("text"),
                "int": .int(42),
                "double": .double(2.718),
                "bool": .bool(true),
                "null": .null
            ]
        )
        XCTAssertEqual(complexSignal.payload["string"]?.stringValue, "text")
        XCTAssertEqual(complexSignal.payload["int"]?.doubleValue, 42.0)
        XCTAssertEqual(complexSignal.payload["double"]?.doubleValue, 2.718)
        XCTAssertEqual(complexSignal.payload["bool"]?.boolValue, true)
        XCTAssertEqual(complexSignal.payload["null"], .null)
    }
    
    /// Test whisper with custom timeout
    func testWhisperCustomTimeout() async throws {
        let bus = CognitiveSignalBus()
        let receiver = TestReceiver(name: "quickReceiver")
        
        receiver.whisperHandler = { _ in
            return ["status": .string("ok")]
        }
        
        await bus.register(receiver)
        
        let signal = CognitiveSignal(name: "quick", payload: [:])
        let whisper = CognitiveWhisper(signal: signal, target: "quickReceiver", timeout: 10.0)
        
        let response = try await bus.whisper(whisper)
        XCTAssertEqual(response?["status"]?.stringValue, "ok")
    }
}
