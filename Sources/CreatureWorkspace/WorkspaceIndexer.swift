// WorkspaceIndexer — recursively index a directory of source files into one
// merged Rosetta trunk, so retrieval and `ask --context` can operate over an
// entire codebase rather than one file at a time.

import Foundation
import CreatureTrunk
#if canImport(CryptoKit)
import CryptoKit
#else
// Apple's own cross-platform implementation of the same API (swift-crypto).
// Only SHA-256 is used, and it is source-identical on both.
import Crypto
#endif

public enum WorkspaceIndexer {

    public static let skippedDirectoryNames: Set<String> = [".build", ".git", "node_modules", ".swiftpm"]

    public static let maxFiles = 500
    public static let maxFileBytes = 512 * 1024
    public static let maxTotalBytes = 16 * 1024 * 1024

    public struct Workspace {
        public let trunk: CodeTrunk
        public let bridge: TrunkBridge
        public let fileCount: Int
        public let hitFileCap: Bool
        public let hitByteCap: Bool
        public let skippedLargeFiles: [String]
        public let indexedFilePaths: [String]
    }

    public static func index(directory: String) -> Workspace {
        let root = URL(fileURLWithPath: directory, isDirectory: true)
        let fileManager = FileManager.default

        var filePaths: [String] = []
        var hitFileCap = false
        var hitByteCap = false
        var totalBytes = 0

        if let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) {
            walk: for case let fileURL as URL in enumerator {
                let isDirectory = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if isDirectory {
                    let name = fileURL.lastPathComponent
                    if skippedDirectoryNames.contains(name) || name.hasPrefix(".") {
                        enumerator.skipDescendants()
                    }
                    continue
                }

                guard Tentacle(filePath: fileURL.path) != nil else { continue }

                if filePaths.count >= maxFiles {
                    hitFileCap = true
                    break walk
                }

                let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                if totalBytes + fileSize > maxTotalBytes {
                    hitByteCap = true
                    break walk
                }

                filePaths.append(fileURL.path)
                totalBytes += fileSize
            }
        }

        var trunk = CodeTrunk()
        var unresolvedEdges: [UnresolvedEdge] = []
        var skippedLargeFiles: [String] = []
        var indexedFilePaths: [String] = []

        for filePath in filePaths {
            guard let tentacle = Tentacle(filePath: filePath) else { continue }

            guard let attributes = try? fileManager.attributesOfItem(atPath: filePath),
                  let size = attributes[.size] as? Int, size <= maxFileBytes else {
                skippedLargeFiles.append(filePath)
                continue
            }

            guard let source = try? String(contentsOfFile: filePath, encoding: .utf8) else {
                continue
            }

            let module = moduleName(forFilePath: filePath, relativeTo: root)
            let (nodes, _, edges) = tentacle.indexWithBridge(source: source, module: module, file: filePath)

            for node in nodes {
                trunk.add(node)
            }
            unresolvedEdges.append(contentsOf: edges)
            indexedFilePaths.append(filePath)
        }

        let bridge = TrunkBridge.resolve(unresolved: unresolvedEdges, against: trunk)

        return Workspace(
            trunk: trunk,
            bridge: bridge,
            fileCount: indexedFilePaths.count,
            hitFileCap: hitFileCap,
            hitByteCap: hitByteCap,
            skippedLargeFiles: skippedLargeFiles,
            indexedFilePaths: indexedFilePaths
        )
    }

    public static func moduleName(forFilePath filePath: String, relativeTo root: URL) -> String {
        let fileURL = URL(fileURLWithPath: filePath)
        let rootPath = root.standardized.path
        let fullPath = fileURL.standardized.path

        guard fullPath.hasPrefix(rootPath) else {
            return fileURL.deletingPathExtension().lastPathComponent
        }

        var relative = String(fullPath.dropFirst(rootPath.count))
        if relative.hasPrefix("/") { relative.removeFirst() }
        let withoutExtension = (relative as NSString).deletingPathExtension
        return withoutExtension.replacingOccurrences(of: "/", with: ".")
    }

    public static func cacheDirectory(forWorkspacePath workspacePath: String) -> URL {
        let standardized = URL(fileURLWithPath: workspacePath).standardized.path
        let hashInput = Data(standardized.utf8)
        let digest = SHA256.hash(data: hashInput)
        let hexString = digest.map { String(format: "%02x", $0) }.joined()
        
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".creature/tree-cache/\(hexString)")
    }

    public static func loadSnapshot(for workspacePath: String, warnings: inout [String]) -> CompletionTreeSnapshot? {
        let dir = cacheDirectory(forWorkspacePath: workspacePath)
        let store = PersistentStore(directory: dir)
        return store.loadLatest(warnings: &warnings)
    }

    public static func saveSnapshot(_ snapshot: CompletionTreeSnapshot, for workspacePath: String) throws {
        let dir = cacheDirectory(forWorkspacePath: workspacePath)
        let store = PersistentStore(directory: dir)
        try store.save(snapshot)
    }

    public static func workspace(from snapshot: CompletionTreeSnapshot) -> Workspace {
        let trunk = CodeTrunk(nodes: snapshot.nodes)
        let bridge = snapshot.bridge ?? TrunkBridge(edges: [])
        let indexedFilePaths = Array(Set(snapshot.nodes.compactMap { $0.span?.file })).sorted()
        return Workspace(
            trunk: trunk,
            bridge: bridge,
            fileCount: indexedFilePaths.count,
            hitFileCap: false,
            hitByteCap: false,
            skippedLargeFiles: [],
            indexedFilePaths: indexedFilePaths
        )
    }

    public static func isSnapshotStale(_ snapshot: CompletionTreeSnapshot, for workspacePath: String) -> Bool {
        let root = URL(fileURLWithPath: workspacePath, isDirectory: true)
        let fileManager = FileManager.default

        var filePaths: [String] = []
        if let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                let isDirectory = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if isDirectory {
                    let name = fileURL.lastPathComponent
                    if skippedDirectoryNames.contains(name) || name.hasPrefix(".") {
                        enumerator.skipDescendants()
                    }
                    continue
                }

                guard Tentacle(filePath: fileURL.path) != nil else { continue }

                let mtime = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                if mtime > snapshot.createdAt {
                    return true
                }
                filePaths.append(fileURL.path)
            }
        }

        let snapshotFiles = Set(snapshot.nodes.compactMap { $0.span?.file })
        if Set(filePaths) != snapshotFiles {
            return true
        }

        return false
    }
}

public enum ContextDefaults {
    public static let contextLimit = 8
    public static let blockCharBudget = 6000
}
