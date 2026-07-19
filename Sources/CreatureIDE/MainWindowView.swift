#if canImport(SwiftUI)
import SwiftUI
import CreatureSpine
import CreatureTrunk
import CreatureWorkspace

struct MainWindowView: View {
    @State private var directoryPath: String = ""
    @State private var selectedNode: TrunkNode?
    @State private var nodes: [TrunkNode] = []
    @State private var leafStatus: [String: TrunkStatus] = [:]
    @State private var rolledUpStatus: [String: TrunkStatus] = [:]
    @State private var diagnostics: [Diagnostic] = []
    @State private var probedFiles: Set<String> = []
    @State private var coverages: [DiagnosticReducer.GrammarCoverage] = []
    
    // Background unconscious logs
    @State private var unconsciousLogs: [String] = [
        "Unconscious core initialized.",
        "Awaiting workspace specification..."
    ]
    
    // Sidebar configurations
    private let sidebarWidth: CGFloat = 260
    private let chatbarWidth: CGFloat = 360
    
    var body: some View {
        VStack(spacing: 0) {
            // 1. Earned Green Status HUD
            GreenStatusHUD(
                nodes: nodes,
                rolledUpStatus: rolledUpStatus,
                diagnostics: diagnostics,
                probedFiles: probedFiles,
                coverages: coverages
            )
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // 2. Main three-column panel body
            HSplitView {
                // Left Column: File Explorer
                FileTreeView(
                    directoryPath: $directoryPath,
                    nodes: $nodes,
                    leafStatus: $leafStatus,
                    rolledUpStatus: $rolledUpStatus,
                    diagnostics: $diagnostics,
                    probedFiles: $probedFiles,
                    coverages: $coverages,
                    selectedNode: $selectedNode,
                    unconsciousLogs: $unconsciousLogs
                )
                .frame(minWidth: sidebarWidth, maxWidth: sidebarWidth + 100)
                .background(Theme.sidebarBackground)
                
                // Center Column: Code Editor/Viewer
                CodeEditorView(selectedNode: selectedNode)
                    .frame(minWidth: 400)
                    .background(Theme.editorBackground)
                
                // Right Column: Conscious / Unconscious Split View Chat
                ChatPaneView(
                    directoryPath: directoryPath,
                    unconsciousLogs: $unconsciousLogs
                )
                .frame(minWidth: chatbarWidth, maxWidth: chatbarWidth + 150)
                .background(Theme.sidebarBackground)
            }
        }
        .preferredColorScheme(.dark)
        .background(Theme.ink)
        .ignoresSafeArea()
    }
}

#endif
