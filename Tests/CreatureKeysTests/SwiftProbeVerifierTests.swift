import Testing
import Foundation
import CreatureSpine
import CreatureTrunkSwift
@testable import CreatureKeys

@Suite struct SwiftProbeVerifierTests {
    /// These tests require a real swiftc. When it is absent, the verifier must degrade
    /// honestly — never report clean — and the assertions below reflect that.
    private var toolchainPresent: Bool { SwiftCompileProbe.locateSwiftc() != nil }

    @Test func cleanSourceTypeChecks() async throws {
        let v = SwiftProbeVerifier()
        let verdict = await v.verify(source: "let x: Int = 1\n")
        if toolchainPresent {
            #expect(verdict.clean)
            #expect(verdict.messages.isEmpty)
        } else {
            #expect(!verdict.clean)                     // honest degrade
            #expect(verdict.unavailableReason != nil)
        }
    }

    @Test func brokenSourceIsNotCleanAndCarriesMessages() async throws {
        let v = SwiftProbeVerifier()
        let verdict = await v.verify(source: "let x: Int = \"not an int\"\n")
        #expect(!verdict.clean)                          // never clean, toolchain or not
        if toolchainPresent {
            #expect(!verdict.messages.isEmpty)           // the compiler's own words, to hand back
        }
    }

    @Test func languageIsSwift() {
        #expect(SwiftProbeVerifier().language == "swift")
    }

    @Test func writesOnlyIntoATemporaryDirectory() async {
        // The verifier must never write into the user's workspace.
        let before = try? FileManager.default.contentsOfDirectory(atPath: FileManager.default.currentDirectoryPath)
        _ = await SwiftProbeVerifier().verify(source: "let x = 1\n")
        let after = try? FileManager.default.contentsOfDirectory(atPath: FileManager.default.currentDirectoryPath)
        #expect(before?.count == after?.count)
    }
}
