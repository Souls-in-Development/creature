import Testing
import Foundation
@testable import CreatureTrunk

@Suite struct PersistentStoreTests {

    // MARK: - Helpers

    private func makeTempDirectory() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )
        return tempDir
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func makeNode(
        id: String,
        path: [String],
        kind: String = "func",
        truthKey: String = "k"
    ) -> TrunkNode {
        TrunkNode(
            id: id,
            coordinate: TrunkCoordinate(
                path: path,
                kind: kind,
                truthKey: truthKey
            ),
            channels: []
        )
    }

    private func makeSimpleSnapshot(createdAt: Date = Date()) -> CompletionTreeSnapshot {
        let nodes = [
            makeNode(id: "module-1", path: ["Demo"], kind: "module", truthKey: "mod"),
            makeNode(id: "type-1", path: ["Demo", "Greeter"], kind: "struct", truthKey: "type"),
            makeNode(id: "func-1", path: ["Demo", "Greeter", "hello"], kind: "func", truthKey: "func"),
        ]
        let tree = TreeIndex.from(nodes: nodes)
        let leafStatus: [String: TrunkStatus] = [
            "module-1": .green,
            "type-1": .green,
            "func-1": .red,
        ]
        let engine = RollUpEngine(tree: tree, leafStatus: leafStatus)
        let rolledUp = engine.compute()
        return CompletionTreeSnapshot(
            createdAt: createdAt,
            nodes: nodes,
            treeIndex: tree,
            leafStatus: leafStatus,
            rolledUpStatus: rolledUp
        )
    }

    private func makeStore(
        maxSnapshots: Int = 3
    ) -> (store: PersistentStore, dir: URL) {
        let dir = makeTempDirectory()
        return (PersistentStore(directory: dir, maxSnapshots: maxSnapshots), dir)
    }

    // MARK: - Basic save / load

    @Test func saveAndLoadRoundTrip() throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let original = makeSimpleSnapshot()
        try store.save(original)

        let loaded = store.loadLatest()
        #expect(loaded != nil)
        #expect(loaded?.version == original.version)
        #expect(loaded?.nodes.count == original.nodes.count)
        #expect(loaded?.leafStatus == original.leafStatus)
        #expect(loaded?.rolledUpStatus == original.rolledUpStatus)
    }

    @Test func loadReturnsNilForEmptyStore() {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let loaded = store.loadLatest()
        #expect(loaded == nil)
    }

    @Test func atlasReconstructionFromSnapshot() throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let original = makeSimpleSnapshot()
        try store.save(original)

        let loaded = store.loadLatest()!
        let atlas = loaded.makeAtlas()

        #expect(atlas.status(for: "func-1") == .red)
        #expect(atlas.status(for: "type-1") == .red)
        #expect(atlas.status(for: "module-1") == .red)
        #expect(atlas.overall == .red)
    }

    // MARK: - Atomicity

    @Test func saveCreatesExactlyOneSnapshotFile() throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        try store.save(makeSimpleSnapshot())
        let files = store.listSnapshotFiles()
        #expect(files.count == 1)
    }

    @Test func tempFilesAreNotLeftBehind() throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        try store.save(makeSimpleSnapshot())

        let allFiles = try FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        )
        let tempFiles = allFiles.filter { $0.lastPathComponent.hasSuffix(".tmp") }
        #expect(tempFiles.isEmpty)
    }

    // MARK: - Snapshot pruning

    @Test func prunesOldSnapshots() throws {
        let (store, dir) = makeStore(maxSnapshots: 2)
        defer { cleanup(dir) }

        try store.save(makeSimpleSnapshot())
        Thread.sleep(forTimeInterval: 0.01)
        try store.save(makeSimpleSnapshot())
        Thread.sleep(forTimeInterval: 0.01)
        try store.save(makeSimpleSnapshot())

        let files = store.listSnapshotFiles()
        #expect(files.count == 2)
    }

    @Test func loadLatestReturnsMostRecent() throws {
        let (store, dir) = makeStore(maxSnapshots: 3)
        defer { cleanup(dir) }

        let snapshot1 = makeSimpleSnapshot()
        try store.save(snapshot1)

        // Small delay to ensure different timestamps
        Thread.sleep(forTimeInterval: 0.01)

        var nodes2 = snapshot1.nodes
        nodes2.append(makeNode(id: "extra", path: ["Extra"], kind: "func", truthKey: "x"))
        let tree2 = TreeIndex.from(nodes: nodes2)
        let snapshot2 = CompletionTreeSnapshot(
            nodes: nodes2,
            treeIndex: tree2,
            leafStatus: snapshot1.leafStatus,
            rolledUpStatus: snapshot1.rolledUpStatus
        )
        try store.save(snapshot2)

        let loaded = store.loadLatest()
        #expect(loaded?.nodes.count == 4)
    }

    // MARK: - Rollback on corruption

    @Test func fallsBackToOlderSnapshotWhenLatestIsCorrupted() throws {
        let (store, dir) = makeStore(maxSnapshots: 3)
        defer { cleanup(dir) }

        try store.save(makeSimpleSnapshot())
        Thread.sleep(forTimeInterval: 0.01)
        try store.save(makeSimpleSnapshot())

        // Corrupt the latest snapshot by truncating it
        let files = store.listSnapshotFiles()
        #expect(files.count == 2)
        let latestFile = files[0]
        let corruptData = Data("{\"version\":1,\"corrupt".utf8)
        try corruptData.write(to: latestFile)

        var warnings: [String] = []
        let loaded = store.loadLatest(warnings: &warnings)
        #expect(loaded != nil)
        #expect(loaded?.nodes.count == 3)
        #expect(!warnings.isEmpty)
    }

    // MARK: - Corruption recovery (lenient load)

    @Test func lenientLoadRecoversValidNodes() throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let original = makeSimpleSnapshot()
        try store.save(original)

        // Corrupt the file by changing a node's id to a number (type mismatch)
        let files = store.listSnapshotFiles()
        #expect(files.count == 1)
        let fileURL = files[0]
        var jsonString = try String(contentsOf: fileURL)
        // Replace a node's id field with a number so JSONDecoder fails for that node
        // but JSONSerialization still parses the overall object.
        jsonString = jsonString.replacingOccurrences(
            of: "\"id\" : \"type-1\"",
            with: "\"id\" : 12345"
        )
        try jsonString.write(to: fileURL, atomically: true, encoding: .utf8)

        var warnings: [String] = []
        let loaded = store.loadLatest(warnings: &warnings)
        #expect(loaded != nil)
        #expect(loaded?.nodes.count == 2) // one node was corrupted
        #expect(warnings.contains(where: { $0.contains("Skipping corrupted node") }))
    }

    @Test func lenientLoadSkipsInvalidStatusEntries() throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let original = makeSimpleSnapshot()
        try store.save(original)

        // Corrupt by adding an invalid raw status value
        let files = store.listSnapshotFiles()
        let fileURL = files[0]
        var jsonString = try String(contentsOf: fileURL)
        jsonString = jsonString.replacingOccurrences(
            of: "\"func-1\" : 2",
            with: "\"func-1\" : 2, \"ghost\" : 99"
        )
        try jsonString.write(to: fileURL, atomically: true, encoding: .utf8)

        var warnings: [String] = []
        let loaded = store.loadLatest(warnings: &warnings)
        #expect(loaded != nil)
        #expect(loaded?.leafStatus["ghost"] == nil)
        #expect(loaded?.leafStatus["func-1"] == .red)
        #expect(warnings.contains(where: { $0.contains("invalid status rawValue 99") }))
    }

    @Test func lenientLoadRebuildsTreeIndexWhenCorrupted() throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let original = makeSimpleSnapshot()
        try store.save(original)

        // Corrupt the treeIndex section
        let files = store.listSnapshotFiles()
        let fileURL = files[0]
        var jsonString = try String(contentsOf: fileURL)
        jsonString = jsonString.replacingOccurrences(
            of: "\"treeIndex\"",
            with: "\"treeIndex\" : {\"broken\" : true}, \"__real_treeIndex\""
        )
        try jsonString.write(to: fileURL, atomically: true, encoding: .utf8)

        var warnings: [String] = []
        let loaded = store.loadLatest(warnings: &warnings)
        #expect(loaded != nil)
        #expect(loaded?.treeIndex.count == original.nodes.count)
        #expect(warnings.contains(where: { $0.contains("Rebuilding TreeIndex") }))
    }

    // MARK: - Version compatibility

    @Test func rejectsFutureVersion() throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let original = makeSimpleSnapshot()
        try store.save(original)

        // Mutate the version to a future number
        let files = store.listSnapshotFiles()
        let fileURL = files[0]
        var jsonString = try String(contentsOf: fileURL)
        jsonString = jsonString.replacingOccurrences(
            of: "\"version\" : 1",
            with: "\"version\" : 999"
        )
        try jsonString.write(to: fileURL, atomically: true, encoding: .utf8)

        var warnings: [String] = []
        let loaded = store.loadLatest(warnings: &warnings)
        #expect(loaded == nil)
        #expect(warnings.contains(where: { $0.contains("unsupported version 999") }))
    }

    // MARK: - Snapshot with bridge

    @Test func roundTripWithBridge() throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let nodes = [
            makeNode(id: "a", path: ["A"]),
            makeNode(id: "b", path: ["B"]),
        ]
        let tree = TreeIndex.from(nodes: nodes)
        let leafStatus: [String: TrunkStatus] = ["a": .green, "b": .red]
        let bridge = TrunkBridge(edges: [
            TrunkEdge(source: "b", target: "a", kind: .call)
        ])
        let engine = RollUpEngine(tree: tree, leafStatus: leafStatus, bridge: bridge)
        let rolledUp = engine.compute()

        let snapshot = CompletionTreeSnapshot(
            nodes: nodes,
            treeIndex: tree,
            leafStatus: leafStatus,
            rolledUpStatus: rolledUp,
            bridge: bridge
        )
        try store.save(snapshot)

        let loaded = store.loadLatest()
        #expect(loaded?.bridge != nil)
        #expect(loaded?.bridge?.edges.count == 1)
        #expect(loaded?.bridge?.edges.first?.source == "b")
    }

    // MARK: - Clear

    @Test func clearRemovesAllSnapshots() throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        try store.save(makeSimpleSnapshot())
        Thread.sleep(forTimeInterval: 0.01)
        try store.save(makeSimpleSnapshot())
        #expect(store.listSnapshotFiles().count == 2)

        try store.clear()
        #expect(store.listSnapshotFiles().isEmpty)
        #expect(store.loadLatest() == nil)
    }

    // MARK: - CompletionTreeSnapshot equatable

    @Test func snapshotEquality() {
        let fixedDate = Date(timeIntervalSince1970: 1_000_000)
        let s1 = makeSimpleSnapshot(createdAt: fixedDate)
        let s2 = makeSimpleSnapshot(createdAt: fixedDate)
        #expect(s1 == s2)
    }

    @Test func snapshotCodableRoundTrip() throws {
        let original = makeSimpleSnapshot()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            CompletionTreeSnapshot.self,
            from: data
        )
        #expect(decoded == original)
    }

    // MARK: - Load by index

    @Test func loadSnapshotByIndex() throws {
        let (store, dir) = makeStore(maxSnapshots: 3)
        defer { cleanup(dir) }

        let s1 = makeSimpleSnapshot()
        try store.save(s1)
        Thread.sleep(forTimeInterval: 0.01)

        var nodes2 = s1.nodes
        nodes2.append(makeNode(id: "extra", path: ["X"]))
        let s2 = CompletionTreeSnapshot(
            nodes: nodes2,
            treeIndex: TreeIndex.from(nodes: nodes2),
            leafStatus: s1.leafStatus,
            rolledUpStatus: s1.rolledUpStatus
        )
        try store.save(s2)

        let latest = store.loadSnapshot(at: 0)
        let previous = store.loadSnapshot(at: 1)

        #expect(latest?.nodes.count == 4)
        #expect(previous?.nodes.count == 3)
    }

    @Test func loadSnapshotAtInvalidIndexReturnsNil() {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let result = store.loadSnapshot(at: 5)
        #expect(result == nil)
    }
}
