import Testing
import Foundation
@testable import CreatureCLI
import CreatureWorkspace
import CreatureTrunk
import CreatureTrunkSwift

/// End-to-end B3.1 tests: index a real temp workspace, run the probe, reduce,
/// and assert the resulting Atlas verdict. This is where the false-green killer
/// is proven at the level the whole feature promises — "see green before you
/// compile" actually meaning the code type-checks.
@Suite struct WorkspaceProbeTests {

    private var swiftcAvailable: Bool { SwiftCompileProbe.locateSwiftc() != nil }

    private func makeWorkspace(_ files: [(name: String, source: String)]) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("creature-workspace-probe-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for file in files {
            try file.source.write(to: root.appendingPathComponent(file.name), atomically: true, encoding: .utf8)
        }
        return root
    }

    // MARK: - Fixture A: the false-green killer (end to end)

    /// A workspace whose Swift file parses cleanly but does NOT type-check.
    /// Under the OLD syntactic-only `indexWithStatus` this whole workspace is
    /// `.green` — that is precisely the false green B3 kills. After probing,
    /// the overall Atlas status must be `.red`.
    @Test func parsesButDoesNotTypeCheckWorkspaceIsRedAfterProbing() throws {
        let root = try makeWorkspace([(
            "Caller.swift",
            """
            func caller() {
                let result = undefinedHelper(41)
                print(result)
            }
            """
        )])
        defer { try? FileManager.default.removeItem(at: root) }

        let workspace = WorkspaceIndexer.index(directory: root.path)

        // Contrast: the syntactic-only leaf statuses are all green (it parses).
        // (This same input is `.green` under `indexWithStatus`; that contrast
        // is the entire point of B3.)
        let syntacticAtlas = TrunkAtlas(trunk: workspace.trunk, leafStatus: [:])
        #expect(syntacticAtlas.overall == .unknown)  // no probe → no certification

        let result = WorkspaceProbe.probe(workspace: workspace)

        guard swiftcAvailable else {
            // No toolchain in this environment → the file is unprobed → the
            // Atlas is `.unknown`. It must NOT falsely pass as red, and must
            // NOT be green.
            #expect(result.atlas.overall == .unknown)
            #expect(result.atlas.overall != .green)
            #expect(result.atlas.overall != .red)
            return
        }

        // With swiftc present (this machine has Xcode): the undefined call is a
        // real type-check error → red.
        #expect(result.atlas.overall == .red)
        #expect(result.diagnostics.contains { $0.severity == .error })
        // And the specific node carrying the error is red, while the workspace
        // is not merely "unknown."
        #expect(result.atlas.overall != .green)
        #expect(result.atlas.overall != .unknown)
    }

    // MARK: - Fixture B: clean workspace, green end to end

    @Test func cleanWorkspaceIsGreenAfterProbing() throws {
        let root = try makeWorkspace([
            ("Math.swift", """
             func add(a: Int, b: Int) -> Int { a + b }
             """),
            ("Use.swift", """
             func total() -> Int { add(a: 1, b: 2) }
             """)
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let workspace = WorkspaceIndexer.index(directory: root.path)
        let result = WorkspaceProbe.probe(workspace: workspace)

        guard swiftcAvailable else {
            #expect(result.atlas.overall == .unknown)
            #expect(result.atlas.overall != .green)
            return
        }

        #expect(result.atlas.overall == .green)
        #expect(result.diagnostics.filter { $0.severity == .error }.isEmpty)
    }

    // MARK: - Fixture C: honest degrade (injected unavailable probe)

    /// Force the probe unavailable by injecting a `SwiftCompileProbe` pointed at
    /// a non-existent compiler. Regardless of whether a real swiftc exists on
    /// the machine, this asserts the honest-degrade contract deterministically:
    /// overall status is `.unknown`, explicitly NOT green and NOT red.
    @Test func unavailableProbeDegradesWorkspaceToUnknown() throws {
        let root = try makeWorkspace([(
            "Any.swift",
            "func f() -> Int { 1 }"
        )])
        defer { try? FileManager.default.removeItem(at: root) }

        let workspace = WorkspaceIndexer.index(directory: root.path)

        let unavailableProbe = SwiftCompileProbe(swiftcOverride: "/nonexistent/definitely/not/swiftc")
        let result = WorkspaceProbe.probe(workspace: workspace, probes: [unavailableProbe])

        #expect(result.atlas.overall == .unknown)
        #expect(result.atlas.overall != .green)   // the whole point of unknown
        #expect(result.atlas.overall != .red)
        #expect(result.unavailable.contains { $0.producer == "swiftc" })
        #expect(result.probedFiles.isEmpty)
    }

    @Test func emptyWorkspaceIsUnknown() throws {
        let root = try makeWorkspace([])
        defer { try? FileManager.default.removeItem(at: root) }

        let workspace = WorkspaceIndexer.index(directory: root.path)
        let result = WorkspaceProbe.probe(workspace: workspace)

        // No nodes at all → nothing was checked → unknown.
        #expect(result.atlas.overall == .unknown)
    }
}
