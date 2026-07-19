#if canImport(SwiftUI)
import SwiftUI
import CreatureChat
import CreatureSpine

struct Message: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    let timestamp: Date
}

struct ChatPaneView: View {
    let directoryPath: String
    @Binding var unconsciousLogs: [String]

    @State private var chatMessages: [Message] = [
        Message(text: "I am the creature. Ask me anything — grounded in this workspace. My first reply may take a moment while the local model loads.", isUser: false, timestamp: Date())
    ]
    @State private var inputText: String = ""
    @State private var isReplying: Bool = false

    /// The real, shared inference pipeline (CreatureChat). Built once the
    /// workspace is indexed; nil until then, which disables sending.
    @State private var engine: ChatEngine?
    @State private var engineReady: Bool = false
    /// After the first reply the model is resident, so later "thinking" waits
    /// are short — only the first one carries the load/download cost.
    @State private var firstReplyDone: Bool = false
    
    var body: some View {
        VSplitView {
            // Top Panel: Conscious Mind Chat
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Text("CONSCIOUS MIND")
                        .font(Theme.mono(10))
                        .foregroundColor(Theme.paper)
                        .fontWeight(.bold)
                    Spacer()
                    Circle()
                        .fill(Theme.teal)
                        .frame(width: 6, height: 6)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.02))
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                // Conversational Message List
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(chatMessages) { msg in
                                HStack {
                                    if msg.isUser { Spacer() }
                                    
                                    VStack(alignment: msg.isUser ? .trailing : .leading, spacing: 4) {
                                        Text(msg.text)
                                            .font(Theme.mono(11))
                                            .foregroundColor(msg.isUser ? Theme.ink : Theme.paper)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(msg.isUser ? Theme.teal : Color.white.opacity(0.06))
                                            .cornerRadius(6)
                                        
                                        Text(msg.isUser ? "User" : "Creature")
                                            .font(Theme.mono(8))
                                            .foregroundColor(Theme.p3)
                                    }
                                    
                                    if !msg.isUser { Spacer() }
                                }
                                .id(msg.id)
                            }
                            
                            if isReplying {
                                HStack {
                                    // The first reply pays the model load (and,
                                    // on a fresh machine, a ~1.6 GB download), so
                                    // say so — otherwise a minute of "thinking"
                                    // reads as a hang.
                                    Text(firstReplyDone
                                         ? "Creature is thinking..."
                                         : "Waking the creature — the first reply loads the local model (first run downloads it, ~1.6 GB)…")
                                        .font(Theme.mono(10))
                                        .foregroundColor(Theme.teal)
                                        .italic()
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: chatMessages.count) { _ in
                        if let last = chatMessages.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                // TextInput
                HStack(spacing: 8) {
                    TextField(engineReady ? "Ask 'the creature'..." : "Indexing workspace…",
                              text: $inputText, onCommit: sendMessage)
                        .textFieldStyle(.plain)
                        .font(Theme.mono(11))
                        .foregroundColor(Theme.paper)
                        .padding(8)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(4)
                        .disabled(!engineReady || isReplying)

                    Button(action: sendMessage) {
                        Image(systemName: "paperplane.fill")
                            .foregroundColor(engineReady && !isReplying ? Theme.teal : Theme.p3)
                    }
                    .buttonStyle(.plain)
                    .disabled(!engineReady || isReplying)
                }
                .padding(12)
                .background(Color.white.opacity(0.02))
            }
            .frame(minHeight: 250)
            
            // Bottom Panel: Unconscious Mind Log
            VStack(alignment: .leading, spacing: 0) {
                Divider()
                    .background(Color.white.opacity(0.1))
                
                // Header
                HStack {
                    Text("UNCONSCIOUS TERMINAL")
                        .font(Theme.mono(10))
                        .foregroundColor(Theme.p3)
                        .fontWeight(.bold)
                    Spacer()
                    Text("BACKGROUND ACTIVITY")
                        .font(Theme.mono(8))
                        .foregroundColor(Theme.gold)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.01))
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                // Scrolling logs
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(0..<unconsciousLogs.count, id: \.self) { idx in
                                Text(unconsciousLogs[idx])
                                    .font(Theme.mono(10))
                                    .foregroundColor(Theme.p3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(idx)
                            }
                        }
                        .padding(12)
                    }
                    .onChange(of: unconsciousLogs.count) { _ in
                        withAnimation {
                            proxy.scrollTo(unconsciousLogs.count - 1, anchor: .bottom)
                        }
                    }
                }
                .background(Color.black.opacity(0.2))
            }
            .frame(minHeight: 150)
        }
        // Keyed on directoryPath: the workspace is empty at launch and the user
        // picks one later in the file tree, so the engine must rebuild when it
        // changes — otherwise chat would stay grounded in the wrong (or no)
        // directory. SwiftUI cancels the prior task and re-runs this on change.
        .task(id: directoryPath) { await setupEngine() }
    }

    /// Build the shared chat engine off the main actor (indexing the workspace is
    /// real work), then enable sending. The model itself loads lazily on the
    /// first message, so this returns as soon as the index is ready. Rebuilds
    /// whenever the chosen workspace changes; an empty path means plain,
    /// un-grounded conversation.
    private func setupEngine() async {
        engineReady = false

        // Use the user's configured slots if present, else zero-setup local souls
        // — so the pane works even before `creature config` has ever run.
        let config = CreatureConfig.load() ?? .defaultLocal
        let dir = directoryPath.isEmpty ? nil : directoryPath
        if let dir { logUnconscious("Indexing workspace at \(dir)…") }

        let built = await Task.detached(priority: .userInitiated) {
            ChatEngine(config: config, contextDirectory: dir)
        }.value

        if dir != nil {
            let files = await built.contextFileCount ?? 0
            let nodes = await built.contextNodeCount ?? 0
            logUnconscious("Indexed \(files) file(s), \(nodes) node(s). Ready.")
        } else {
            logUnconscious("Ready — no workspace selected, chatting without code grounding.")
        }

        engine = built
        engineReady = true
    }

    private func logUnconscious(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = formatter.string(from: Date())
        unconsciousLogs.append("[\(timestamp)] \(message)")
    }
    
    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isReplying else { return }
        guard let engine else {
            logUnconscious("Still indexing the workspace — one moment.")
            return
        }

        chatMessages.append(Message(text: trimmed, isUser: true, timestamp: Date()))
        inputText = ""
        isReplying = true
        logUnconscious("Query received — routing + grounding: \"\(trimmed)\"")

        Task {
            let reply = await engine.send(trimmed)
            await MainActor.run {
                isReplying = false
                firstReplyDone = true

                if reply.reindexedCount > 0 {
                    logUnconscious("Workspace changed — re-indexed \(reply.reindexedCount) file(s).")
                }

                guard reply.isSuccess else {
                    chatMessages.append(Message(
                        text: "⚠ \(reply.errorDescription ?? "generation failed")",
                        isUser: false, timestamp: Date()
                    ))
                    logUnconscious("Error: \(reply.errorDescription ?? "unknown")")
                    return
                }

                chatMessages.append(Message(text: reply.text, isUser: false, timestamp: Date()))

                let role = reply.isCoordinated
                    ? "coordinated"
                    : (reply.role == .conscious ? "conscious" : "unconscious")
                logUnconscious("Answered by \(role) · \(Int(reply.latencyMs))ms · \(Int(reply.confidence * 100))% confidence")
                if !reply.contextPaths.isEmpty {
                    logUnconscious("Grounded in: \(reply.contextPaths.joined(separator: ", "))")
                }
            }
        }
    }
}

#endif
