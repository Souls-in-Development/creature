#if canImport(SwiftUI)
import SwiftUI
import CreatureSpine
import CreatureTrunk
import CreatureWorkspace

struct FileTreeView: View {
    @Binding var directoryPath: String
    @Binding var nodes: [TrunkNode]
    @Binding var leafStatus: [String: TrunkStatus]
    @Binding var rolledUpStatus: [String: TrunkStatus]
    @Binding var diagnostics: [Diagnostic]
    @Binding var probedFiles: Set<String>
    @Binding var coverages: [DiagnosticReducer.GrammarCoverage]
    @Binding var selectedNode: TrunkNode?
    @Binding var unconsciousLogs: [String]
    
    @State private var statusMessage: String = "No workspace loaded"
    @State private var isLoading: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("PROJECT")
                .font(Theme.mono(10))
                .foregroundColor(Theme.p3)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)
            
            // Path input
            HStack(spacing: 8) {
                TextField("Workspace dir path", text: $directoryPath)
                    .textFieldStyle(.plain)
                    .font(Theme.mono(11))
                    .foregroundColor(Theme.paper)
                    .padding(6)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(4)
                
                Button(action: loadWorkspace) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(Theme.teal)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Status bar message
            Text(statusMessage)
                .font(Theme.mono(10))
                .foregroundColor(Theme.teal)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.02))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // List of nodes
            if isLoading {
                VStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.8)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(nodes, id: \.id) { node in
                            let status = rolledUpStatus[node.id] ?? .unknown
                            let isSelected = selectedNode?.id == node.id
                            
                            Button(action: { selectedNode = node }) {
                                HStack(spacing: 8) {
                                    // Indentation
                                    let indent = CGFloat(max(0, node.coordinate.depth - 1)) * 12
                                    Spacer()
                                        .frame(width: indent)
                                    
                                    // Status indicator
                                    Circle()
                                        .fill(colorFor(status: status))
                                        .frame(width: 7, height: 7)
                                    
                                    // Node Kind Tag
                                    Text(node.coordinate.kind)
                                        .font(Theme.mono(8))
                                        .foregroundColor(Theme.teal.opacity(0.8))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Theme.teal.opacity(0.1))
                                        .cornerRadius(2)
                                    
                                    // Node name
                                    let baseName = node.coordinate.pathKey.components(separatedBy: ".").last ?? node.coordinate.pathKey
                                    Text(baseName)
                                        .font(Theme.mono(11))
                                        .foregroundColor(isSelected ? Theme.teal : Theme.paper)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                                .background(isSelected ? Color.white.opacity(0.06) : Color.clear)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }
    
    private func colorFor(status: TrunkStatus) -> Color {
        switch status {
        case .green: return Theme.green
        case .yellow: return Theme.gold
        case .red: return Theme.red
        case .unknown: return Theme.p3
        }
    }
    
    private func logUnconscious(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = formatter.string(from: Date())
        unconsciousLogs.append("[\(timestamp)] \(message)")
    }
    
    private func loadWorkspace() {
        guard !directoryPath.isEmpty else {
            statusMessage = "Please specify a directory"
            return
        }
        
        let path = directoryPath
        isLoading = true
        statusMessage = "Scanning workspace..."
        
        let log: @Sendable (String) -> Void = { message in
            DispatchQueue.main.async {
                self.logUnconscious(message)
            }
        }
        
        log("Initiated directory scan on: \(path)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            var loadedWS: WorkspaceIndexer.Workspace
            var warnings: [String] = []
            var isCached = false
            var finalLeafStatus: [String: TrunkStatus] = [:]
            var finalRolledUpStatus: [String: TrunkStatus] = [:]
            var finalDiagnostics: [Diagnostic] = []
            var finalProbedFiles: Set<String> = []
            var finalCoverages: [DiagnosticReducer.GrammarCoverage] = []
            
            // Check cache
            log("Checking ~/.creature/tree-cache/ for active snapshot...")
            if let snapshot = WorkspaceIndexer.loadSnapshot(for: path, warnings: &warnings),
               !WorkspaceIndexer.isSnapshotStale(snapshot, for: path) {
                log("Found valid, non-stale snapshot. Loading from cache...")
                loadedWS = WorkspaceIndexer.workspace(from: snapshot)
                finalLeafStatus = snapshot.leafStatus
                finalRolledUpStatus = snapshot.rolledUpStatus
                finalProbedFiles = Set(snapshot.nodes.compactMap { $0.span?.file })
                isCached = true
            } else {
                log("Cache stale or empty. Indexing files...")
                let fresh = WorkspaceIndexer.index(directory: path)
                loadedWS = fresh
                
                log("Indexed \(fresh.fileCount) files, \(fresh.trunk.nodes.count) nodes.")
                log("Executing real compile-readiness probes (B3.1)...")
                
                let result = WorkspaceProbe.probe(workspace: fresh)
                
                finalLeafStatus = result.atlas.leafStatus
                
                // Roll up statuses
                let treeIndex = TreeIndex.from(nodes: fresh.trunk.nodes)
                let engine = RollUpEngine(tree: treeIndex, leafStatus: finalLeafStatus, bridge: fresh.bridge)
                finalRolledUpStatus = engine.compute()
                
                finalDiagnostics = result.diagnostics
                finalProbedFiles = result.probedFiles
                finalCoverages = result.coverages
                
                log("Probe completed: \(result.diagnostics.count) diagnostic(s) reported.")
                log("Saving snapshot to tree cache...")
                
                // Save snapshot
                let snapshot = CompletionTreeSnapshot(
                    nodes: fresh.trunk.nodes,
                    treeIndex: treeIndex,
                    leafStatus: finalLeafStatus,
                    rolledUpStatus: finalRolledUpStatus,
                    bridge: fresh.bridge
                )
                try? WorkspaceIndexer.saveSnapshot(snapshot, for: path)
            }
            
            DispatchQueue.main.async {
                self.nodes = loadedWS.trunk.nodes
                self.leafStatus = finalLeafStatus
                self.rolledUpStatus = finalRolledUpStatus
                self.diagnostics = finalDiagnostics
                self.probedFiles = finalProbedFiles
                self.coverages = finalCoverages
                self.isLoading = false
                self.statusMessage = isCached ? "Loaded from cache" : "Workspace indexed"
                self.logUnconscious(isCached ? "Workspace loaded from cache." : "Probed and cached successfully.")
                if self.selectedNode == nil {
                    self.selectedNode = loadedWS.trunk.nodes.first
                }
            }
        }
    }
}

#endif
