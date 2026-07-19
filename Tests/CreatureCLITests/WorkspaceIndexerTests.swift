import Testing
import Foundation
@testable import CreatureCLI
import CreatureWorkspace
import CreatureTrunk

@Suite struct WorkspaceIndexerTests {

    /// Write a tiny two-file Swift workspace to a temp directory: `Caller.swift`
    /// defines `orchestrate()` which calls `helper()`, defined in
    /// `Helper.swift` — a real cross-file call, the thing single-file indexing
    /// cannot resolve but workspace indexing should.
    private func makeTempWorkspace() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("creature-workspace-indexer-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let callerSource = """
        func orchestrate() {
            helper()
        }
        """
        try callerSource.write(to: root.appendingPathComponent("Caller.swift"), atomically: true, encoding: .utf8)

        let helperSource = """
        func helper() {
            print("helping")
        }
        """
        try helperSource.write(to: root.appendingPathComponent("Helper.swift"), atomically: true, encoding: .utf8)

        // A non-source file that should simply be ignored.
        try "not code".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        // A .build-like directory that must be skipped entirely.
        let buildDir = root.appendingPathComponent(".build", isDirectory: true)
        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
        try "func shouldNotBeIndexed() {}".write(to: buildDir.appendingPathComponent("Ignored.swift"), atomically: true, encoding: .utf8)

        return root
    }

    @Test func indexesAllSourceFilesAndSkipsNonSource() throws {
        let root = try makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let workspace = WorkspaceIndexer.index(directory: root.path)

        #expect(workspace.fileCount == 2) // Caller.swift + Helper.swift, not README.md
        #expect(workspace.trunk.nodes.contains { $0.coordinate.path.last == "orchestrate" })
        #expect(workspace.trunk.nodes.contains { $0.coordinate.path.last == "helper" })
        #expect(!workspace.hitFileCap)
        #expect(!workspace.hitByteCap)
    }

    @Test func skipsBuildDirectoryEntirely() throws {
        let root = try makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let workspace = WorkspaceIndexer.index(directory: root.path)

        #expect(!workspace.trunk.nodes.contains { $0.coordinate.path.last == "shouldNotBeIndexed" })
    }

    @Test func crossFileCallResolvesViaMergedBridge() throws {
        let root = try makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let workspace = WorkspaceIndexer.index(directory: root.path)

        guard let orchestrateNode = workspace.trunk.nodes.first(where: { $0.coordinate.path.last == "orchestrate" }),
              let helperNode = workspace.trunk.nodes.first(where: { $0.coordinate.path.last == "helper" }) else {
            Issue.record("expected both orchestrate and helper nodes in the merged trunk")
            return
        }

        let targets = workspace.bridge.targets(of: orchestrateNode.id)
        #expect(targets.contains(helperNode.id))
    }

    @Test func moduleNameReflectsRelativeDirectoryStructure() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("creature-workspace-module-name-tests-\(UUID().uuidString)", isDirectory: true)
        let subdir = root.appendingPathComponent("Sub", isDirectory: true)
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let filePath = subdir.appendingPathComponent("Thing.swift").path
        let module = WorkspaceIndexer.moduleName(forFilePath: filePath, relativeTo: root)
        #expect(module == "Sub.Thing")
    }

    @Test func emptyDirectoryProducesEmptyWorkspace() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("creature-workspace-empty-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let workspace = WorkspaceIndexer.index(directory: root.path)
        #expect(workspace.fileCount == 0)
        #expect(workspace.trunk.nodes.isEmpty)
        #expect(workspace.bridge.edges.isEmpty)
    }
}
