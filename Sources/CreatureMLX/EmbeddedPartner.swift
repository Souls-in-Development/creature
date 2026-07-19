// Apple-only. MLX is Metal / Apple-Silicon-only, so off Apple this whole file
// compiles away and CreatureMLX becomes an empty module — which is what lets
// `swift build` succeed on Linux and Windows. A "local:" slot there is served by
// a local model server instead; see `makePartner` in CreatureChat.
#if canImport(MLXLMCommon)

// EmbeddedPartner — runs an LLM in-process via MLX-Swift (Apple Silicon, Metal).
//
// This is the "the creature runs its own model" partner: no external server,
// no Ollama/LM Studio. First use downloads the model (mlx-community, 4-bit)
// via the Hugging Face Hub client into the standard HF cache
// (~/.cache/huggingface/hub) and holds it resident in-process for reuse.
//
// Conforms to `LLMPartner` from CreatureSpine so it is interchangeable with
// `HTTPPartner` behind the conscious/unconscious slots.
//
// API surface verified against the checked-out mlx-swift-lm 3.31.3 sources
// (`.build/checkouts/mlx-swift-lm/`), not the (stale) README:
//   - `MLXHuggingFace` provides `#huggingFaceLoadModelContainer(configuration:progressHandler:)`,
//     a macro that wires `HuggingFace.HubClient()` as the `Downloader` and
//     `Tokenizers.AutoTokenizer` (via swift-transformers) as the `TokenizerLoader`
//     behind `LLMModelFactory.shared.loadContainer(from:using:configuration:progressHandler:)`.
//   - `ModelContainer.prepare(input:) async throws -> LMInput` and
//     `ModelContainer.generate(input:parameters:) async throws -> AsyncStream<Generation>`
//     are the modern, non-closure entry points (avoid the deprecated
//     `perform { context in ... }` pattern, which also trips Swift 6 Sendable
//     checks on non-Sendable `UserInput`/`LMInput` captures).

import Foundation
import CreatureSpine
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

/// Errors specific to in-process MLX inference.
public enum EmbeddedPartnerError: Error, CustomStringConvertible {
    case modelLoadFailed(String)
    case generationFailed(String)

    public var description: String {
        switch self {
        case .modelLoadFailed(let msg): return "MLX model load failed: \(msg)"
        case .generationFailed(let msg): return "MLX generation failed: \(msg)"
        }
    }
}

/// An `LLMPartner` backed by an MLX-Swift model running in-process on
/// Apple Silicon. Downloads + caches the model on first use via the
/// Hugging Face Hub client (`~/.cache/huggingface/hub`).
public actor EmbeddedPartner: LLMPartner {
    nonisolated public let metadata: PartnerMetadata

    /// Hugging Face repo id, e.g. "mlx-community/Qwen2.5-3B-Instruct-4bit".
    private let modelId: String

    /// Lazily-loaded, cached model container. Loaded once, reused across calls.
    private var container: ModelContainer?

    /// Optional callback for download/load progress (0.0...1.0).
    private let onProgress: (@Sendable (Double) -> Void)?

    public init(
        modelId: String,
        preferredRole: PartnerRole,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) {
        self.modelId = modelId
        self.onProgress = onProgress
        self.metadata = PartnerMetadata(
            name: modelId,
            provider: "mlx-swift (in-process)",
            preferredRole: preferredRole,
            latencyMs: 0
        )
    }

    /// Loads (or returns the cached) model container.
    private func loadedContainer() async throws -> ModelContainer {
        if let container {
            return container
        }

        let configuration = MLXLMCommon.ModelConfiguration(id: modelId)

        do {
            let loaded = try await #huggingFaceLoadModelContainer(
                configuration: configuration
            ) { progress in
                self.onProgress?(progress.fractionCompleted)
            }
            self.container = loaded
            return loaded
        } catch {
            throw EmbeddedPartnerError.modelLoadFailed("\(error)")
        }
    }

    public func complete(prompt: String, system: String?) async throws -> String {
        let container = try await loadedContainer()

        var messages: [Chat.Message] = []
        if let system, !system.isEmpty {
            messages.append(.system(system))
        }
        messages.append(.user(prompt))

        let userInput = UserInput(chat: messages)

        do {
            let lmInput = try await container.prepare(input: userInput)
            let stream = try await container.generate(
                input: lmInput,
                parameters: GenerateParameters(temperature: 0.7)
            )

            var generated = ""
            for await item in stream {
                if case .chunk(let text) = item {
                    generated += text
                }
            }
            return generated
        } catch {
            throw EmbeddedPartnerError.generationFailed("\(error)")
        }
    }
}

#endif
