// WorkspaceWatcher — mtime-based staleness detection for long-lived sessions

import Foundation
import CreatureTrunk

public struct WorkspaceWatcher {

    public private(set) var recordedModificationDates: [String: Date]
    private let directory: String

    public init(directory: String) {
        self.directory = Self.canonicalize(directory)
        self.recordedModificationDates = Self.currentModificationDates(directory: self.directory)
    }

    private static func canonicalize(_ path: String) -> String {
        var buffer = [Int8](repeating: 0, count: Int(PATH_MAX))
        guard realpath(path, &buffer) != nil else { return path }
        return buffer.withUnsafeBufferPointer { pointer in
            String(cString: pointer.baseAddress!)
        }
    }

    public enum Change: Equatable {
        case modified(path: String)
        case added(path: String)
        case removed(path: String)
    }

    public func detectChanges() -> [Change] {
        let current = Self.currentModificationDates(directory: directory)
        var changes: [Change] = []

        for (path, recordedDate) in recordedModificationDates {
            guard let currentDate = current[path] else {
                changes.append(.removed(path: path))
                continue
            }
            if currentDate != recordedDate {
                changes.append(.modified(path: path))
            }
        }

        for path in current.keys where recordedModificationDates[path] == nil {
            changes.append(.added(path: path))
        }

        return changes.sorted { lhs, rhs in lhs.path < rhs.path }
    }

    public mutating func refresh() {
        recordedModificationDates = Self.currentModificationDates(directory: directory)
    }

    private static func currentModificationDates(directory: String) -> [String: Date] {
        let root = URL(fileURLWithPath: directory, isDirectory: true)
        let fileManager = FileManager.default
        var result: [String: Date] = [:]

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return result
        }

        for case let fileURL as URL in enumerator {
            let isDirectory = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory {
                let name = fileURL.lastPathComponent
                if WorkspaceIndexer.skippedDirectoryNames.contains(name) || name.hasPrefix(".") {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard Tentacle(filePath: fileURL.path) != nil else { continue }

            let modificationDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            result[fileURL.path] = modificationDate
        }

        return result
    }
}

public extension WorkspaceWatcher.Change {
    var path: String {
        switch self {
        case .modified(let path), .added(let path), .removed(let path):
            return path
        }
    }
}
