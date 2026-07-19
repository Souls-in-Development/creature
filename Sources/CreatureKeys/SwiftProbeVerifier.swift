import Foundation
import CreatureSpine
import CreatureTrunk
import CreatureTrunkSwift

/// THE BOUND, as a `CodeVerifier`.
///
/// Citation buys well-formed blocks. It cannot buy *agreement* between them — that a name
/// exists, that a type fits. Only the compiler can say that, and it says it exactly once,
/// by exiting 0. `scopeClean` is therefore the only thing that sets `clean`; the absence
/// of diagnostics never does.
///
/// The source is written to a fresh temporary directory and probed there. Nothing is ever
/// written into the user's workspace.
public struct SwiftProbeVerifier: CodeVerifier {
    public let language = "swift"
    public init() {}

    public func verify(source: String) async -> VerifierVerdict {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("creature-cite-\(UUID().uuidString)")
        let file = dir.appendingPathComponent("Cited.swift")

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try source.write(to: file, atomically: true, encoding: .utf8)
        } catch {
            return .unavailable("could not stage source: \(error.localizedDescription)")
        }
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = SwiftCompileProbe().probe(files: [file.path])

        if let reason = result.unavailableReason {
            return .unavailable(reason)
        }
        let errors = result.diagnostics
            .filter { $0.severity == .error }
            .map { "line \($0.startLine): \($0.message)" }

        return VerifierVerdict(clean: result.scopeClean, messages: errors)
    }
}
