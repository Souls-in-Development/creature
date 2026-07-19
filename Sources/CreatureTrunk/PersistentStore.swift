import Foundation

/// A versioned, self-contained snapshot of the completion-tree state.
///
/// Contains everything needed to reconstruct a `TrunkAtlas` without
/// re-indexing or re-computing roll-ups.
public struct CompletionTreeSnapshot: Sendable, Codable, Equatable {
    public static let currentVersion = 1

    public let version: Int
    public let createdAt: Date
    public let nodes: [TrunkNode]
    public let treeIndex: TreeIndex
    public let leafStatus: [String: TrunkStatus]
    public let rolledUpStatus: [String: TrunkStatus]
    public let bridge: TrunkBridge?

    public init(
        version: Int = currentVersion,
        createdAt: Date = Date(),
        nodes: [TrunkNode],
        treeIndex: TreeIndex,
        leafStatus: [String: TrunkStatus],
        rolledUpStatus: [String: TrunkStatus],
        bridge: TrunkBridge? = nil
    ) {
        self.version = version
        self.createdAt = createdAt
        self.nodes = nodes
        self.treeIndex = treeIndex
        self.leafStatus = leafStatus
        self.rolledUpStatus = rolledUpStatus
        self.bridge = bridge
    }

    /// Reconstruct a `TrunkAtlas` from this snapshot.
    public func makeAtlas() -> TrunkAtlas {
        let trunk = CodeTrunk(nodes: nodes)
        return TrunkAtlas(trunk: trunk, leafStatus: leafStatus, bridge: bridge)
    }
}

/// Errors thrown by `PersistentStore`.
public enum PersistentStoreError: Error, Sendable {
    case writeFailed
    case invalidFormat
    case unsupportedVersion(Int)
}

/// Atomic, versioned persistence for completion-tree snapshots.
///
/// Guarantees:
/// - Every `save` is atomic (write temp → fsync → rename).
/// - Load skips corrupted snapshots and tries older ones (rollback).
/// - Lenient load recovers valid entries from partially-corrupted data.
/// - Only the latest `maxSnapshots` are kept; older ones are pruned.
public struct PersistentStore: Sendable {
    public let directory: URL
    public let maxSnapshots: Int

    private let filenamePrefix = "completion-tree"
    private let filenameExtension = "json"

    public init(directory: URL, maxSnapshots: Int = 3) {
        self.directory = directory
        self.maxSnapshots = maxSnapshots
    }

    // MARK: - Save

    /// Atomically save a snapshot to disk.
    ///
    /// Writes to a temporary file, fsyncs, then atomically replaces the
    /// destination. Prunes older snapshots so at most `maxSnapshots` remain.
    public func save(_ snapshot: CompletionTreeSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(snapshot)

        let filename = makeFilename(for: snapshot.createdAt)
        let fileURL = directory.appendingPathComponent(filename)
        let tempURL = directory
            .appendingPathComponent(".\(filename).\(UUID().uuidString).tmp")

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        // Write to temp file
        guard FileManager.default.createFile(
            atPath: tempURL.path,
            contents: nil,
            attributes: nil
        ) else {
            throw PersistentStoreError.writeFailed
        }

        let handle = try FileHandle(forWritingTo: tempURL)
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()

        // Atomic replace.
        //
        // NOT `FileManager.replaceItemAt`: on Darwin it atomically swaps, but
        // swift-corelibs-foundation implements it differently and the file does
        // not land when the destination does not already exist — so every first
        // save silently produced nothing on Linux, and the read back failed with
        // "file doesn't exist". Call rename(2) directly instead: it is atomic,
        // it overwrites, and it is what Darwin's implementation ultimately does,
        // so the behaviour is now identical on both.
        #if canImport(Darwin) || canImport(Glibc)
        guard rename(tempURL.path, fileURL.path) == 0 else {
            try? FileManager.default.removeItem(at: tempURL)
            throw PersistentStoreError.writeFailed
        }
        #else
        // Windows' rename refuses an existing destination, so clear it first.
        // Not atomic, but it is the only option the platform offers here.
        try? FileManager.default.removeItem(at: fileURL)
        try FileManager.default.moveItem(at: tempURL, to: fileURL)
        #endif

        // Fsync directory to ensure the rename is durable
        syncDirectory(at: directory)

        // Prune old snapshots
        try pruneOldSnapshots()
    }

    // MARK: - Load

    /// Load the latest valid snapshot.
    ///
    /// Tries snapshots from newest to oldest. On corruption, collects
    /// warnings and attempts lenient recovery. Returns `nil` when no
    /// snapshot exists or all snapshots are unreadable.
    public func loadLatest(warnings: inout [String]) -> CompletionTreeSnapshot? {
        let files = listSnapshotFiles()
        for (index, fileURL) in files.enumerated() {
            var fileWarnings: [String] = []
            if let snapshot = loadSnapshot(
                from: fileURL,
                warnings: &fileWarnings
            ) {
                warnings.append(contentsOf: fileWarnings)
                if !fileWarnings.isEmpty && index > 0 {
                    warnings.append(
                        "Recovered from older snapshot: \(fileURL.lastPathComponent)"
                    )
                }
                return snapshot
            }
            warnings.append(contentsOf: fileWarnings)
        }
        return nil
    }

    /// Convenience overload that discards warnings.
    public func loadLatest() -> CompletionTreeSnapshot? {
        var warnings: [String] = []
        return loadLatest(warnings: &warnings)
    }

    /// Load a specific snapshot by index (`0` = latest, `1` = second-latest).
    public func loadSnapshot(
        at index: Int,
        warnings: inout [String]
    ) -> CompletionTreeSnapshot? {
        let files = listSnapshotFiles()
        guard index >= 0, index < files.count else { return nil }
        return loadSnapshot(from: files[index], warnings: &warnings)
    }

    /// Convenience overload that discards warnings.
    public func loadSnapshot(at index: Int) -> CompletionTreeSnapshot? {
        var warnings: [String] = []
        return loadSnapshot(at: index, warnings: &warnings)
    }

    /// List all snapshot files, newest first.
    public func listSnapshotFiles() -> [URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        return files
            .filter {
                $0.lastPathComponent.hasPrefix(filenamePrefix)
                    && $0.pathExtension == filenameExtension
            }
            .sorted { a, b in
                let dateA = (try? a.resourceValues(forKeys: [.creationDateKey])
                    .creationDate) ?? Date.distantPast
                let dateB = (try? b.resourceValues(forKeys: [.creationDateKey])
                    .creationDate) ?? Date.distantPast
                return dateA > dateB
            }
    }

    /// Delete all snapshots.
    public func clear() throws {
        for fileURL in listSnapshotFiles() {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    // MARK: - Private

    private func makeFilename(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        let timestamp = formatter.string(from: date)
        return "\(filenamePrefix)-\(timestamp).\(filenameExtension)"
    }

    private func loadSnapshot(
        from fileURL: URL,
        warnings: inout [String]
    ) -> CompletionTreeSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else {
            warnings.append(
                "Could not read data from \(fileURL.lastPathComponent)"
            )
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Try strict decode first
        if let snapshot = try? decoder.decode(
            CompletionTreeSnapshot.self,
            from: data
        ) {
            if snapshot.version > CompletionTreeSnapshot.currentVersion {
                warnings.append(
                    "Snapshot \(fileURL.lastPathComponent) has unsupported version \(snapshot.version)"
                )
                return nil
            }
            return snapshot
        }

        // Try lenient recovery
        do {
            let snapshot = try loadLenient(
                from: data,
                fileName: fileURL.lastPathComponent,
                warnings: &warnings
            )
            warnings.append(
                "Recovered partial data from corrupted snapshot \(fileURL.lastPathComponent)"
            )
            return snapshot
        } catch {
            warnings.append(
                "Failed to recover \(fileURL.lastPathComponent): \(error)"
            )
            return nil
        }
    }

    /// Attempt to recover valid entries from corrupted JSON data.
    private func loadLenient(
        from data: Data,
        fileName: String,
        warnings: inout [String]
    ) throws -> CompletionTreeSnapshot {
        guard let json = try JSONSerialization.jsonObject(with: data)
            as? [String: Any]
        else {
            throw PersistentStoreError.invalidFormat
        }

        let version = json["version"] as? Int ?? 0
        if version > CompletionTreeSnapshot.currentVersion {
            throw PersistentStoreError.unsupportedVersion(version)
        }

        let createdAtString = json["createdAt"] as? String ?? ""
        let createdAt = ISO8601DateFormatter().date(from: createdAtString)
            ?? Date()

        // Recover nodes
        var validNodes: [TrunkNode] = []
        if let nodesArray = json["nodes"] as? [[String: Any]] {
            for (index, nodeDict) in nodesArray.enumerated() {
                if let nodeData = try? JSONSerialization.data(
                    withJSONObject: nodeDict
                ),
                    let node = try? JSONDecoder().decode(
                        TrunkNode.self,
                        from: nodeData
                    )
                {
                    validNodes.append(node)
                } else {
                    warnings.append(
                        "Skipping corrupted node at index \(index) in \(fileName)"
                    )
                }
            }
        }

        // Recover tree index (strict, or rebuild from nodes)
        let treeIndex: TreeIndex
        if let treeIndexData = try? JSONSerialization.data(
            withJSONObject: json["treeIndex"] ?? [:]
        ),
            let decodedIndex = try? JSONDecoder().decode(
                TreeIndex.self,
                from: treeIndexData
            ),
            decodedIndex.count > 0
        {
            treeIndex = decodedIndex
        } else {
            warnings.append(
                "Rebuilding TreeIndex from recovered nodes in \(fileName)"
            )
            treeIndex = TreeIndex.from(nodes: validNodes)
        }

        // Recover leafStatus
        var leafStatus: [String: TrunkStatus] = [:]
        if let statusDict = json["leafStatus"] as? [String: Int] {
            for (key, rawValue) in statusDict {
                if let status = TrunkStatus(rawValue: rawValue) {
                    leafStatus[key] = status
                } else {
                    warnings.append(
                        "Skipping invalid status rawValue \(rawValue) for key '\(key)' in \(fileName)"
                    )
                }
            }
        }

        // Recover rolledUpStatus
        var rolledUpStatus: [String: TrunkStatus] = [:]
        if let statusDict = json["rolledUpStatus"] as? [String: Int] {
            for (key, rawValue) in statusDict {
                if let status = TrunkStatus(rawValue: rawValue) {
                    rolledUpStatus[key] = status
                } else {
                    warnings.append(
                        "Skipping invalid rolledUpStatus rawValue \(rawValue) for key '\(key)' in \(fileName)"
                    )
                }
            }
        }

        // Recover bridge
        var bridge: TrunkBridge? = nil
        if let bridgeDict = json["bridge"] as? [String: Any],
            let bridgeData = try? JSONSerialization.data(
                withJSONObject: bridgeDict
            ),
            let decodedBridge = try? JSONDecoder().decode(
                TrunkBridge.self,
                from: bridgeData
            )
        {
            bridge = decodedBridge
        }

        return CompletionTreeSnapshot(
            version: version,
            createdAt: createdAt,
            nodes: validNodes,
            treeIndex: treeIndex,
            leafStatus: leafStatus,
            rolledUpStatus: rolledUpStatus,
            bridge: bridge
        )
    }

    private func pruneOldSnapshots() throws {
        let snapshots = listSnapshotFiles()
        guard snapshots.count > maxSnapshots else { return }
        for fileURL in snapshots.suffix(from: maxSnapshots) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    private func syncDirectory(at url: URL) {
        // Best-effort directory fsync. On some platforms opening a directory
        // via FileHandle is not supported; we silently skip in that case.
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        try? handle.synchronize()
        try? handle.close()
    }
}
