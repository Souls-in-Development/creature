// CreatureChat — the headless chat pipeline, shared by the CLI and the IDE.
//
// This module exists because the whole inference pipeline used to live in
// CreatureCLI/main.swift, an *executable* target. Executables cannot be
// imported, so the IDE could not reach a single line of it — its chat pane was
// a hardcoded string. Everything the CLI's `chat` command actually does is now
// here, behind `ChatEngine`, so both surfaces drive the same code.
//
// Nothing in this module prints or uses ANSI. It returns structured values; how
// they are shown (a terminal line, a SwiftUI bubble) is the caller's business.

import Foundation
// On Linux/Windows, Foundation's networking lives in a separate module.
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import CreatureSpine
import CreatureInference
#if canImport(CreatureMLX)
import CreatureMLX
#endif

// MARK: - HTTP LLM partner

/// An `LLMPartner` that talks to any OpenAI-compatible API — Claude via proxy,
/// Qwen, DeepSeek, Ollama, LM Studio, and so on.
public struct HTTPPartner: LLMPartner {
    public let metadata: PartnerMetadata
    public let baseURL: String
    public let apiKey: String
    public let model: String

    public init(metadata: PartnerMetadata, baseURL: String, apiKey: String, model: String) {
        self.metadata = metadata
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
    }

    public func complete(prompt: String, system: String?) async throws -> String {
        var messages: [[String: Any]] = []
        if let sys = system {
            messages.append(["role": "system", "content": sys])
        }
        messages.append(["role": "user", "content": prompt])

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "max_tokens": 2048,
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: URL(string: "\(baseURL)/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw PartnerError.httpError(status, String(data: data, encoding: .utf8) ?? "")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let content = message?["content"] as? String

        return content ?? ""
    }
}

public enum PartnerError: Error {
    case httpError(Int, String)
    case noContent
}

// MARK: - Slot provider (local-or-remote)

/// A slot's `URL` field is either a remote OpenAI-compatible endpoint
/// (e.g. "http://localhost:11434") or, when prefixed with "local:", an
/// in-process MLX model id to run via `EmbeddedPartner`
/// (e.g. "local:mlx-community/Qwen2.5-3B-Instruct-4bit"). This keeps
/// `CreatureConfig` a single flat, backward-compatible shape while letting
/// either slot be local-or-remote independently.
public enum SlotProvider {
    case local(modelId: String)
    case remote(url: String)

    public static let localPrefix = "local:"

    public static func parse(_ raw: String) -> SlotProvider {
        if raw.hasPrefix(localPrefix) {
            return .local(modelId: String(raw.dropFirst(localPrefix.count)))
        }
        return .remote(url: raw)
    }

    public var configValue: String {
        switch self {
        case .local(let modelId): return "\(Self.localPrefix)\(modelId)"
        case .remote(let url): return url
        }
    }

    public var isLocal: Bool {
        if case .local = self { return true }
        return false
    }
}

// MARK: - Partner construction

/// Where a "local:" slot goes when this machine has no in-process engine.
///
/// MLX is Apple-Silicon-only, so off Apple there is nothing to run a model
/// *inside* the process. "Local" then means the next most local thing: a model
/// server running on this same machine. Ollama's OpenAI-compatible API is the
/// default because it is the one people already have on Windows and Linux.
/// Override with `CREATURE_LOCAL_SERVER` (e.g. LM Studio on :1234).
public var defaultLocalServerURL: String {
    ProcessInfo.processInfo.environment["CREATURE_LOCAL_SERVER"] ?? "http://localhost:11434"
}

/// Builds an `LLMPartner` for a slot from config.
///
/// A "local:<model>" slot means *run it on this machine*, and how that happens
/// depends on the machine:
///
/// - **Apple Silicon** — in-process via MLX (`EmbeddedPartner`). Nothing else to
///   install; the model is downloaded and run inside the creature.
/// - **Everywhere else** — a local model server (Ollama by default) over the
///   same OpenAI-compatible seam a remote slot uses. Still local, still private,
///   just a separate process. `<model>` is then an Ollama model name
///   (e.g. "qwen2.5-coder"), not an MLX repo id.
///
/// A "remote:" slot is unchanged on every platform. This is the single seam
/// every command (ask/chat/calibrate) uses, so both slots stay independently
/// local-or-remote everywhere.
public func makePartner(
    url: String,
    key: String,
    model: String,
    role: PartnerRole,
    onProgress: (@Sendable (Double) -> Void)? = nil
) -> any LLMPartner {
    switch SlotProvider.parse(url) {
    case .local(let modelId):
        #if canImport(CreatureMLX)
        return EmbeddedPartner(modelId: modelId, preferredRole: role, onProgress: onProgress)
        #else
        // No in-process engine on this platform — drive a local model server.
        let server = defaultLocalServerURL
        return HTTPPartner(
            metadata: PartnerMetadata(name: modelId, provider: server, preferredRole: role, latencyMs: 0),
            baseURL: server,
            apiKey: key,
            model: modelId
        )
        #endif
    case .remote(let remoteURL):
        return HTTPPartner(
            metadata: PartnerMetadata(name: model, provider: remoteURL, preferredRole: role, latencyMs: 0),
            baseURL: remoteURL,
            apiKey: key,
            model: model
        )
    }
}
