// WorkspaceProbe — compile-readiness probes over an already-indexed workspace

import Foundation
import CreatureTrunk
import CreatureTrunkSwift

public enum WorkspaceProbe {

    public struct Result {
        public let atlas: TrunkAtlas
        public let diagnostics: [Diagnostic]
        public let probedFiles: Set<String>
        public let unavailable: [(producer: String, reason: String)]
        public let coverages: [DiagnosticReducer.GrammarCoverage]
        public let readiness: [String: NodeReadiness]
    }

    /// The probes run by default: Swift's real `swiftc` type-check, plus one
    /// external single-file validator per universal language (`ruby -c`,
    /// `node --check`, …). Every probe honestly degrades to UNKNOWN when its
    /// tool is absent, so this is safe to run anywhere — an uninstalled
    /// toolchain simply leaves that language unchecked rather than guessing.
    public static let defaultProbes: [CompileProbe] = [SwiftCompileProbe()] + ExternalToolProbe.registry

    public static func probe(
        workspace: WorkspaceIndexer.Workspace,
        probes: [CompileProbe] = WorkspaceProbe.defaultProbes
    ) -> Result {
        let files = workspace.indexedFilePaths

        var coverages: [DiagnosticReducer.GrammarCoverage] = []
        var allDiagnostics: [Diagnostic] = []
        var probedFiles: Set<String> = []
        var unavailable: [(producer: String, reason: String)] = []
        var usrMaps: [String: [String: String]] = [:]  // language → usrMap

        for probe in probes {
            let result = probe.probe(files: files)

            if let swiftProbe = probe as? SwiftCompileProbe,
               let spatialIndex = swiftProbe.spatialIndex {
                var usrMap: [String: String] = [:]
                for node in workspace.trunk.nodes {
                    guard let span = node.span else { continue }
                    if let usr = spatialIndex.usrFor(filePath: span.file, line: span.startLine) {
                        usrMap[usr] = node.id
                    }
                }
                usrMaps[swiftProbe.language] = usrMap
            }

            let unit: String
            if result.probedFiles.count == 1, let first = result.probedFiles.first {
                unit = URL(fileURLWithPath: first).deletingPathExtension().lastPathComponent
            } else {
                unit = "workspace"
            }

            let coverage = DiagnosticReducer.GrammarCoverage(
                language: probe.language,
                probedFiles: result.probedFiles,
                diagnostics: result.diagnostics,
                scopeClean: result.scopeClean,
                usrMap: usrMaps[probe.language],
                unit: unit,
                condition: "unconditioned"
            )
            coverages.append(coverage)
            allDiagnostics.append(contentsOf: result.diagnostics)
            probedFiles.formUnion(result.probedFiles)
            if let reason = result.unavailableReason {
                unavailable.append((producer: probe.producer, reason: reason))
            }
        }

        let readiness = DiagnosticReducer.reduce(coverages: coverages, trunk: workspace.trunk)
        let leafStatus = readiness.mapValues { TrunkStatus.from(readiness: $0) }

        let atlas = TrunkAtlas(
            trunk: workspace.trunk,
            leafStatus: leafStatus,
            bridge: workspace.bridge
        )

        return Result(
            atlas: atlas,
            diagnostics: allDiagnostics,
            probedFiles: probedFiles,
            unavailable: unavailable,
            coverages: coverages,
            readiness: readiness
        )
    }
}
