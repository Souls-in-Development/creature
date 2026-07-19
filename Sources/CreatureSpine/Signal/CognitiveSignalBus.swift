//
//  CognitiveSignalBus.swift
//  CreatureSpine
//
//  Unified signal bus with typed payloads for creature cognition.
//  Supports whispers (directed request-response) and pulses (broadcast).
//

import Foundation

// MARK: - Error Types

/// Errors that can occur during signal bus operations
public enum CognitiveSignalError: Error, Equatable {
    /// The specified receiver was not found in the registry
    case receiverNotFound(String)
    /// A whisper operation timed out waiting for response
    case timeout(String)
    /// The payload format was invalid or malformed
    case invalidPayload(String)
}

// MARK: - Signal Types

/// A cognitive signal with a name and typed payload
public struct CognitiveSignal: Codable, Equatable, Sendable {
    /// Unique signal name (e.g., "feeling.update", "trail.mark")
    public let name: String
    
    /// Payload dictionary containing signal data
    public let payload: [String: AnyCodable]
    
    /// Timestamp when the signal was created
    public let timestamp: Date
    
    /// Create a new cognitive signal
    /// - Parameters:
    ///   - name: Unique signal identifier
    ///   - payload: Signal data as key-value pairs
    ///   - timestamp: Creation time (defaults to now)
    public init(name: String, payload: [String: AnyCodable], timestamp: Date = Date()) {
        self.name = name
        self.payload = payload
        self.timestamp = timestamp
    }
    
    /// Create a signal with a simple string payload
    public init(name: String, value: String, timestamp: Date = Date()) {
        self.name = name
        self.payload = ["value": .string(value)]
        self.timestamp = timestamp
    }
    
    /// Create a signal with a numeric payload
    public init(name: String, value: Double, timestamp: Date = Date()) {
        self.name = name
        self.payload = ["value": .double(value)]
        self.timestamp = timestamp
    }
}

/// A directed request-response signal with timeout
public struct CognitiveWhisper: Codable, Equatable, Sendable {
    /// The signal being sent
    public let signal: CognitiveSignal
    
    /// Target receiver name
    public let targetReceiver: String
    
    /// Maximum time to wait for response
    public let timeout: TimeInterval
    
    /// Create a new whisper
    /// - Parameters:
    ///   - signal: The signal to send
    ///   - target: Receiver name
    ///   - timeout: Response timeout in seconds (default 5.0)
    public init(signal: CognitiveSignal, target: String, timeout: TimeInterval = 5.0) {
        self.signal = signal
        self.targetReceiver = target
        self.timeout = timeout
    }
}

/// A broadcast signal to interested receivers
public struct CognitivePulse: Codable, Equatable, Sendable {
    /// The signal being broadcast
    public let signal: CognitiveSignal
    
    /// Receivers who have expressed interest (empty = all receivers)
    public let interestedReceivers: [String]
    
    /// Create a new pulse
    /// - Parameters:
    ///   - signal: The signal to broadcast
    ///   - interestedReceivers: Specific receivers (empty = broadcast to all)
    public init(signal: CognitiveSignal, interestedReceivers: [String] = []) {
        self.signal = signal
        self.interestedReceivers = interestedReceivers
    }
}

// MARK: - Receiver Protocol

/// Protocol for objects that can receive cognitive signals
/// Uses AnyObject so both classes and actors can conform.
/// `Sendable` because receivers are captured across task-group boundaries in `whisper(_:)`.
public protocol CognitiveReceiver: AnyObject, Sendable {
    /// Unique receiver identifier
    var receiverName: String { get }
    
    /// Set of signal names this receiver is interested in
    var interestedSignals: Set<String> { get }
    
    /// Handle a whisper (directed request-response)
    /// - Parameter whisper: The whisper to handle
    /// - Returns: Response payload, or nil for no response
    func handleWhisper(_ whisper: CognitiveWhisper) async throws -> [String: AnyCodable]?
    
    /// Handle a pulse (broadcast)
    /// - Parameter pulse: The pulse to handle
    func handlePulse(_ pulse: CognitivePulse) async
}

// MARK: - AnyCodable Helper

/// Type-erased codable wrapper for signal payloads
public enum AnyCodable: Codable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodable])
    case dictionary([String: AnyCodable])
    case null
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode([AnyCodable].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: AnyCodable].self) {
            self = .dictionary(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unable to decode value"
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch self {
        case .null:
            try container.encodeNil()
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .dictionary(let value):
            try container.encode(value)
        }
    }
    
    /// Extract the underlying value as a String
    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
    
    /// Extract the underlying value as a Double
    public var doubleValue: Double? {
        if case .double(let value) = self { return value }
        if case .int(let value) = self { return Double(value) }
        return nil
    }
    
    /// Extract the underlying value as a Bool
    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    /// Extract the underlying value as an Int
    public var intValue: Int? {
        if case .int(let value) = self { return value }
        if case .double(let value) = self { return Int(value) }
        return nil
    }
}

// MARK: - Signal Bus Actor

/// Central bus for cognitive signal routing
/// Supports whispers (directed) and pulses (broadcast) with timeout handling
public actor CognitiveSignalBus {
    /// Registered receivers keyed by name
    private var receivers: [String: WeakCognitiveReceiver] = [:]
    
    /// Registered signal names
    private var registeredSignals: Set<String> = []
    
    /// Initialize the signal bus
    public init() {}
    
    /// Register a receiver to receive signals
    /// - Parameter receiver: The receiver to register
    public func register(_ receiver: CognitiveReceiver) {
        receivers[receiver.receiverName] = WeakCognitiveReceiver(receiver)
    }
    
    /// Unregister a receiver
    /// - Parameter receiverName: Name of receiver to remove
    /// - Returns: True if receiver was found and removed
    @discardableResult
    public func unregister(_ receiverName: String) -> Bool {
        return receivers.removeValue(forKey: receiverName) != nil
    }
    
    /// Send a directed whisper with timeout
    /// - Parameter whisper: The whisper to send
    /// - Returns: Response payload from the receiver
    /// - Throws: CognitiveSignalError.receiverNotFound if target doesn't exist
    /// - Throws: CognitiveSignalError.timeout if response not received in time
    public func whisper(_ whisper: CognitiveWhisper) async throws -> [String: AnyCodable]? {
        guard let weakReceiver = receivers[whisper.targetReceiver],
              let receiver = weakReceiver.receiver else {
            throw CognitiveSignalError.receiverNotFound(whisper.targetReceiver)
        }
        
        // Use withThrowingTaskGroup for timeout handling
        return try await withThrowingTaskGroup(of: ([String: AnyCodable]?).self) { group in
            // Task to wait for receiver response
            group.addTask {
                return try await receiver.handleWhisper(whisper)
            }
            
            // Task to enforce timeout
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(whisper.timeout * 1_000_000_000))
                throw CognitiveSignalError.timeout("Whisper to \(whisper.targetReceiver) timed out after \(whisper.timeout)s")
            }
            
            // Wait for first result (response or timeout)
            let result = try await group.next()!
            
            // Cancel remaining tasks
            group.cancelAll()
            
            return result
        }
    }
    
    /// Broadcast a pulse to interested receivers
    /// - Parameter pulse: The pulse to broadcast
    /// - Returns: Number of receivers that handled the pulse
    public func pulse(_ pulse: CognitivePulse) async -> Int {
        var handledCount = 0
        
        for (name, weakReceiver) in receivers {
            guard let receiver = weakReceiver.receiver else {
                continue
            }
            
            // Check if receiver is interested
            let isInterested = pulse.interestedReceivers.isEmpty ||
                              pulse.interestedReceivers.contains(name) ||
                              receiver.interestedSignals.contains(pulse.signal.name)
            
            if isInterested {
                Task {
                    await receiver.handlePulse(pulse)
                }
                handledCount += 1
            }
        }
        
        return handledCount
    }
    
    /// Register a new signal type
    /// - Parameter signalName: Unique signal identifier
    public func registerSignal(_ signalName: String) {
        registeredSignals.insert(signalName)
    }
    
    /// Check if a signal is registered
    /// - Parameter signalName: Signal to check
    /// - Returns: True if signal is registered
    public func isSignalRegistered(_ signalName: String) -> Bool {
        return registeredSignals.contains(signalName)
    }
    
    /// Get the count of registered receivers
    /// - Returns: Number of currently registered receivers
    public func receiverCount() -> Int {
        // Clean up nil references and return count
        receivers = receivers.filter { $0.value.receiver != nil }
        return receivers.count
    }
    
    /// Get registered signal names
    /// - Returns: Set of registered signal names
    public func registeredSignalsList() -> Set<String> {
        return registeredSignals
    }
}

// MARK: - Weak Reference Wrapper

/// Weak reference wrapper for receivers to prevent retain cycles
private final class WeakCognitiveReceiver: @unchecked Sendable {
    weak var receiver: CognitiveReceiver?
    
    init(_ receiver: CognitiveReceiver) {
        self.receiver = receiver
    }
}
