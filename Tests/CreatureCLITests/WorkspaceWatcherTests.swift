import Testing
import Foundation
@testable import CreatureCLI
import CreatureWorkspace
import CreatureTrunk

@Suite struct WorkspaceWatcherTests {

    /// Returns a freshly created temp directory, canonicalized via
    /// `realpath(3)` — on macOS `NSTemporaryDirectory()` yields a path
    /// through the `/var` symlink (`/var/folders/...`) while
    /// `FileManager`'s enumerator (and thus `WorkspaceWatcher`, which
    /// canonicalizes internally) reports the resolved `/private/var/...`
    /// form. Canonicalizing here means paths built from `root` in these
    /// tests match what `WorkspaceWatcher.detectChanges()` actually reports,
    /// rather than the test comparing two different spellings of the same
    /// file.
    private func makeTempWorkspace() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("creature-workspace-watcher-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        var buffer = [Int8](repeating: 0, count: Int(PATH_MAX))
        guard realpath(root.path, &buffer) != nil else { return root }
        let resolved = buffer.withUnsafeBufferPointer { pointer in
            String(cString: pointer.baseAddress!)
        }
        return URL(fileURLWithPath: resolved, isDirectory: true)
    }

    /// Advance a file's modification date so `detectChanges()` sees a real
    /// diff even if the write happens within the same filesystem timestamp
    /// tick as the initial snapshot.
    private func touch(_ url: URL, secondsFromNow: TimeInterval) throws {
        let newDate = Date().addingTimeInterval(secondsFromNow)
        try FileManager.default.setAttributes([.modificationDate: newDate], ofItemAtPath: url.path)
    }

    @Test func noChangesReportsEmpty() throws {
        let root = try makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        try "func a() {}".write(to: root.appendingPathComponent("A.swift"), atomically: true, encoding: .utf8)

        let watcher = WorkspaceWatcher(directory: root.path)
        #expect(watcher.detectChanges().isEmpty)
    }

    @Test func detectsModifiedFile() throws {
        let root = try makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let fileURL = root.appendingPathComponent("A.swift")
        try "func a() {}".write(to: fileURL, atomically: true, encoding: .utf8)

        let watcher = WorkspaceWatcher(directory: root.path)
        #expect(watcher.detectChanges().isEmpty)

        try "func a() { print(\"changed\") }".write(to: fileURL, atomically: true, encoding: .utf8)
        try touch(fileURL, secondsFromNow: 5)

        let changes = watcher.detectChanges()
        #expect(changes.contains(.modified(path: fileURL.path)))
    }

    @Test func detectsAddedFile() throws {
        let root = try makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        try "func a() {}".write(to: root.appendingPathComponent("A.swift"), atomically: true, encoding: .utf8)

        let watcher = WorkspaceWatcher(directory: root.path)
        #expect(watcher.detectChanges().isEmpty)

        let newFile = root.appendingPathComponent("B.swift")
        try "func b() {}".write(to: newFile, atomically: true, encoding: .utf8)

        let changes = watcher.detectChanges()
        #expect(changes.contains(.added(path: newFile.path)))
    }

    @Test func detectsRemovedFile() throws {
        let root = try makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let fileURL = root.appendingPathComponent("A.swift")
        try "func a() {}".write(to: fileURL, atomically: true, encoding: .utf8)

        let watcher = WorkspaceWatcher(directory: root.path)
        #expect(watcher.detectChanges().isEmpty)

        try FileManager.default.removeItem(at: fileURL)

        let changes = watcher.detectChanges()
        #expect(changes.contains(.removed(path: fileURL.path)))
    }

    @Test func refreshResetsBaselineSoChangesAreNotReReported() throws {
        let root = try makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let fileURL = root.appendingPathComponent("A.swift")
        try "func a() {}".write(to: fileURL, atomically: true, encoding: .utf8)

        var watcher = WorkspaceWatcher(directory: root.path)
        try "func a() { print(\"changed\") }".write(to: fileURL, atomically: true, encoding: .utf8)
        try touch(fileURL, secondsFromNow: 5)

        #expect(!watcher.detectChanges().isEmpty)

        watcher.refresh()
        #expect(watcher.detectChanges().isEmpty)
    }

    /// The deterministic end-to-end proof the spec asks for: touching a file
    /// mid-session is detected by the watcher, and re-indexing the workspace
    /// after that detection picks up a brand-new declaration the original
    /// index never saw — without needing a live model anywhere in the loop.
    @Test func reindexAfterDetectedChangePicksUpNewDeclaration() throws {
        let root = try makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let fileURL = root.appendingPathComponent("A.swift")
        try "func original() {}".write(to: fileURL, atomically: true, encoding: .utf8)

        var workspace = WorkspaceIndexer.index(directory: root.path)
        var watcher = WorkspaceWatcher(directory: root.path)

        #expect(workspace.trunk.nodes.contains { $0.coordinate.path.last == "original" })
        #expect(!workspace.trunk.nodes.contains { $0.coordinate.path.last == "freshlyAdded" })
        #expect(watcher.detectChanges().isEmpty)

        // Simulate an edit mid-session: append a new declaration to the file.
        try """
        func original() {}
        func freshlyAdded() {}
        """.write(to: fileURL, atomically: true, encoding: .utf8)
        try touch(fileURL, secondsFromNow: 5)

        let changes = watcher.detectChanges()
        #expect(changes == [.modified(path: fileURL.path)])

        // Whole-workspace re-index (v0 design — see WorkspaceWatcher's doc
        // comment) picks up the new declaration.
        workspace = WorkspaceIndexer.index(directory: root.path)
        watcher.refresh()

        #expect(workspace.trunk.nodes.contains { $0.coordinate.path.last == "freshlyAdded" })
        #expect(watcher.detectChanges().isEmpty)
    }
}
