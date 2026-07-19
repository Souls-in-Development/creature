#if canImport(SwiftUI)
import SwiftUI
import CreatureTrunk

struct CodeEditorView: View {
    let selectedNode: TrunkNode?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tab header
            HStack {
                if let node = selectedNode {
                    Text(node.coordinate.pathKey)
                        .font(Theme.mono(11))
                        .foregroundColor(Theme.paper)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Theme.editorBackground)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
                } else {
                    Text("No file open")
                        .font(Theme.mono(11))
                        .foregroundColor(Theme.p3)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                Spacer()
            }
            .background(Color.white.opacity(0.02))
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Editor code area
            if let node = selectedNode, let content = node.channel(at: 1)?.content {
                ScrollView {
                    HStack(alignment: .top, spacing: 12) {
                        // Gutter line numbers
                        let lines = content.components(separatedBy: .newlines)
                        VStack(alignment: .trailing, spacing: 0) {
                            ForEach(0..<lines.count, id: \.self) { idx in
                                Text("\(idx + 1)")
                                    .font(Theme.mono(11))
                                    .foregroundColor(Color.white.opacity(0.15))
                                    .frame(height: 18)
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.leading, 8)
                        
                        // Code lines
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(0..<lines.count, id: \.self) { idx in
                                Text(lines[idx])
                                    .font(Theme.mono(11))
                                    .foregroundColor(Theme.paper)
                                    .frame(height: 18)
                            }
                        }
                        .padding(.vertical, 12)
                        
                        Spacer()
                    }
                }
            } else {
                VStack {
                    Spacer()
                    Text("Select a structure in the project tree to view its source code.")
                        .font(Theme.mono(11))
                        .foregroundColor(Theme.p3)
                        .multilineTextAlignment(.center)
                        .padding(40)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

#endif
