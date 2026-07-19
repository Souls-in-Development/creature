#if canImport(SwiftUI)
import SwiftUI
import CreatureTrunk
import CreatureWorkspace

struct GreenStatusHUD: View {
    let nodes: [TrunkNode]
    let rolledUpStatus: [String: TrunkStatus]
    let diagnostics: [Diagnostic]
    let probedFiles: Set<String>
    let coverages: [DiagnosticReducer.GrammarCoverage]
    
    /// The HUD's verdict is the ENGINE's verdict — `TrunkStatus.worst(of:)` over
    /// the rolled-up statuses, never a hand-rolled precedence here.
    ///
    /// Two things this must not do, both of which are false-greens (see THE BOUND
    /// in `TrunkStatus`): rank `unknown` below `green` (an unprobed node blocks a
    /// confident green — `green < unknown` in the semantic ordering), and read
    /// `leafStatus`, which has not had edge propagation applied. `worst(of:)`
    /// already yields `.unknown` for an empty collection, so emptiness cannot
    /// certify health either.
    private var overallStatus: TrunkStatus {
        TrunkStatus.worst(of: rolledUpStatus.values)
    }
    
    var body: some View {
        HStack(spacing: 24) {
            // Logo / Title
            HStack(spacing: 8) {
                Text("C R E A T U R E")
                    .font(Theme.spaceGrotesk(14, weight: .bold))
                    .foregroundColor(Theme.paper)
                Text("IDE")
                    .font(Theme.mono(10))
                    .foregroundColor(Theme.teal)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Theme.teal.opacity(0.15))
                    .cornerRadius(3)
            }
            
            Spacer()
            
            // Stats Panel
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Text("FILES:")
                        .font(Theme.mono(10))
                        .foregroundColor(Theme.p3)
                    Text("\(probedFiles.count)")
                        .font(Theme.mono(11))
                        .foregroundColor(Theme.paper)
                }
                
                HStack(spacing: 4) {
                    Text("NODES:")
                        .font(Theme.mono(10))
                        .foregroundColor(Theme.p3)
                    Text("\(nodes.count)")
                        .font(Theme.mono(11))
                        .foregroundColor(Theme.paper)
                }
            }
            
            // Diagnostics Summary
            HStack(spacing: 12) {
                let errors = diagnostics.filter { $0.severity == .error }.count
                let warnings = diagnostics.filter { $0.severity == .warning }.count
                
                if errors > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.octagon.fill")
                            .foregroundColor(Theme.red)
                            .font(.system(size: 11))
                        Text("\(errors) ERR")
                            .font(Theme.mono(10))
                            .foregroundColor(Theme.red)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Theme.red.opacity(0.12))
                    .cornerRadius(4)
                }
                
                if warnings > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(Theme.gold)
                            .font(.system(size: 11))
                        Text("\(warnings) WARN")
                            .font(Theme.mono(10))
                            .foregroundColor(Theme.gold)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Theme.gold.opacity(0.12))
                    .cornerRadius(4)
                }
            }
            
            // Overall Status Glow Badge
            HStack(spacing: 8) {
                Circle()
                    .fill(badgeColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: badgeColor, radius: 4)
                
                Text(badgeText)
                    .font(Theme.mono(10))
                    .foregroundColor(badgeColor)
                    .fontWeight(.bold)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(badgeColor.opacity(0.1))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(badgeColor.opacity(0.25), lineWidth: 1)
            )
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Theme.ink.opacity(0.95))
    }
    
    private var badgeColor: Color {
        switch overallStatus {
        case .green: return Theme.green
        case .yellow: return Theme.gold
        case .red: return Theme.red
        case .unknown: return Theme.p3
        }
    }
    
    private var badgeText: String {
        switch overallStatus {
        case .green: return "EARNED GREEN"
        case .yellow: return "CAUTION (WARNINGS)"
        case .red: return "UNCLEAN (ERRORS)"
        case .unknown: return "UNCHECKED"
        }
    }
}

#endif
