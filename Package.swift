// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "CreatureSpine",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "CreatureSpine", targets: ["CreatureSpine"]),
        .library(name: "CreatureInference", targets: ["CreatureInference"]),
        .library(name: "CreatureTrunk", targets: ["CreatureTrunk"]),
        .library(name: "CreatureTrunkSwift", targets: ["CreatureTrunkSwift"]),
        .library(name: "CreatureTrunkPython", targets: ["CreatureTrunkPython"]),
        .library(name: "CreatureTrunkFoundation", targets: ["CreatureTrunkFoundation"]),
        .library(name: "CreatureSnippets", targets: ["CreatureSnippets"]),
        .library(name: "CreatureKeys", targets: ["CreatureKeys"]),
        .library(name: "CreatureWorkspace", targets: ["CreatureWorkspace"]),
        .library(name: "CreatureChat", targets: ["CreatureChat"]),
        .library(name: "CreatureMLX", targets: ["CreatureMLX"]),
        .executable(name: "snippets", targets: ["CreatureSnippetsCLI"]),
        .executable(name: "creature", targets: ["CreatureCLI"]),
        .executable(name: "creature-ide", targets: ["CreatureIDE"])
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.31.3"),
        // mlx-swift-lm's Downloader/TokenizerLoader protocols need a real Hugging Face
        // Hub client + tokenizer (BPE + Jinja chat templates) behind them; swift-transformers
        // provides both (Hub, Tokenizers products) and is the officially-documented pairing
        // (see MLXHuggingFace's macro doc comments in the checked-out mlx-swift-lm source).
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.3"),
        // Explicit dependency (not just transitive via swift-transformers/Hub): EmbeddedPartner
        // imports `HuggingFace` directly for `HubClient()`, per the MLXHuggingFace macro contract.
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.8.1"),
        // Already pulled transitively by mlx-swift-lm (resolved to 603.0.2 in
        // Package.resolved). Pinned here to that exact version with `.exact`
        // so CreatureTrunkSwift's direct dependency cannot force a different
        // resolution than what mlx-swift-lm already settled on.
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "603.0.2"),
        // Apple's own cross-platform CryptoKit. On Apple platforms the code uses
        // the system CryptoKit; elsewhere it falls back to this, which exposes an
        // identical SHA-256 API. Declared so non-Apple builds can link it.
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0")
    ],
    targets: [
        .target(
            name: "CreatureSpine",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux, .windows, .android]))
            ],
            exclude: [
                "CHANGELOG.atlas",
                "Auth/CHANGELOG.atlas",
                "Bridge/CHANGELOG.atlas",
                "Colour/CHANGELOG.atlas",
                "Identity/CHANGELOG.atlas",
                "Signal/CHANGELOG.atlas",
                "Sync/CHANGELOG.atlas"
            ]
        ),
        // Portable: learned routing + the Foundation (Apple Intelligence) oracle.
        // FoundationModels is a system framework behind `#if canImport`, so this
        // target carries NO package dependencies and builds on any platform.
        .target(
            name: "CreatureInference",
            dependencies: ["CreatureSpine"]
        ),
        // The ONLY Apple-locked inference target: in-process MLX. MLX is
        // Metal/Apple-Silicon-only, so everything that needs it lives here and
        // nowhere else. Off Apple, a "local:" slot drives a local model server
        // (Ollama) instead — see `makePartner`.
        .target(
            name: "CreatureMLX",
            dependencies: [
                "CreatureSpine",
                // Apple-only. Off Apple this target has no dependencies and its
                // source compiles away to an empty module (see EmbeddedPartner),
                // so `swift build` succeeds on Linux/Windows without ever
                // building MLX.
                .product(name: "MLXLLM", package: "mlx-swift-lm", condition: .when(platforms: [.macOS, .iOS])),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm", condition: .when(platforms: [.macOS, .iOS])),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm", condition: .when(platforms: [.macOS, .iOS])),
                .product(name: "Hub", package: "swift-transformers", condition: .when(platforms: [.macOS, .iOS])),
                .product(name: "Tokenizers", package: "swift-transformers", condition: .when(platforms: [.macOS, .iOS])),
                .product(name: "HuggingFace", package: "swift-huggingface", condition: .when(platforms: [.macOS, .iOS]))
            ]
        ),
        .target(
            name: "CreatureTrunk",
            dependencies: [
                "CreatureSpine",
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux, .windows, .android]))
            ]
        ),
        // Swift cephalopod's first tentacle: an accurate, AST-based Swift
        // indexer built on SwiftSyntax/SwiftParser. Kept as its own target so
        // the core CreatureTrunk stays dependency-light — SwiftSyntax (a
        // sizeable dependency) lives only here.
        .target(
            name: "CreatureTrunkSwift",
            dependencies: [
                "CreatureTrunk",
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux, .windows, .android])),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ]
        ),
        // Python cephalopod's first tentacle: an `ast`-based Python indexer.
        // No SwiftSyntax equivalent exists for Python, so this tentacle shells
        // out to the system `python3` and lets Python's own `ast` module do
        // the parsing — kept as its own target (depending only on
        // CreatureTrunk) so the core trunk stays free of any particular
        // language's tooling, exactly like CreatureTrunkSwift.
        .target(
            name: "CreatureTrunkPython",
            dependencies: ["CreatureTrunk"]
        ),
        // Foundation-assist for the tentacles: generalises `RouteClassifier`
        // (CreatureInference) from "which soul handles this prompt" to "what
        // kind of code is this node" — a semantic dimension the syntactic
        // tentacles (CreatureTrunkSwift/CreatureTrunkPython) cannot derive on
        // their own. Deliberately depends on CreatureTrunk ONLY, not
        // CreatureInference: it needs the system FoundationModels framework
        // (Apple Intelligence), never MLX, and stays light so the trunk can be
        // classified without pulling in the full local-model stack.
        .target(
            name: "CreatureTrunkFoundation",
            dependencies: ["CreatureTrunk"]
        ),
        .target(
            name: "CreatureSnippets",
            dependencies: [],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "CreatureSnippetsCLI",
            dependencies: ["CreatureSnippets"]
        ),
        .target(
            name: "CreatureKeys",
            dependencies: ["CreatureSpine", "CreatureSnippets", "CreatureTrunk", "CreatureTrunkSwift"]
        ),
        .testTarget(
            name: "CreatureKeysTests",
            dependencies: ["CreatureKeys"]
        ),
        .target(
            name: "CreatureWorkspace",
            dependencies: [
                "CreatureSpine",
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux, .windows, .android])),
                "CreatureTrunk",
                "CreatureTrunkSwift",
                "CreatureTrunkPython",
                "CreatureTrunkFoundation",
                "CreatureSnippets"
            ]
        ),
        // The headless chat pipeline (partners, grounding, routing, context, and
        // the ChatEngine) extracted out of CreatureCLI so the IDE can import it —
        // the same move as CreatureWorkspace, one level up: this is where
        // workspace context meets inference.
        .target(
            name: "CreatureChat",
            dependencies: [
                "CreatureSpine",
                "CreatureInference",
                .target(name: "CreatureMLX", condition: .when(platforms: [.macOS, .iOS])),
                "CreatureTrunk",
                "CreatureWorkspace",
                "CreatureSnippets"
            ]
        ),
        .executableTarget(
            name: "CreatureCLI",
            dependencies: ["CreatureChat", "CreatureWorkspace", "CreatureSpine", "CreatureInference", .target(name: "CreatureMLX", condition: .when(platforms: [.macOS, .iOS])), "CreatureTrunk", "CreatureTrunkSwift", "CreatureTrunkPython", "CreatureTrunkFoundation", "CreatureSnippets", "CreatureKeys"],
            exclude: ["CHANGELOG.atlas"]
        ),
        .executableTarget(
            name: "CreatureIDE",
            dependencies: ["CreatureChat", "CreatureWorkspace", "CreatureSpine", "CreatureInference", .target(name: "CreatureMLX", condition: .when(platforms: [.macOS, .iOS])), "CreatureTrunk", "CreatureTrunkSwift", "CreatureTrunkPython", "CreatureTrunkFoundation", "CreatureSnippets", "CreatureKeys"]
        ),
        .testTarget(
            name: "CreatureSpineTests",
            dependencies: ["CreatureSpine"],
            exclude: ["CHANGELOG.atlas"]
        ),
        .testTarget(
            name: "CreatureTrunkTests",
            dependencies: ["CreatureTrunk"]
        ),
        .testTarget(
            name: "CreatureTrunkSwiftTests",
            dependencies: ["CreatureTrunkSwift"]
        ),
        .testTarget(
            name: "CreatureTrunkPythonTests",
            dependencies: ["CreatureTrunkPython", "CreatureTrunkSwift"]
        ),
        .testTarget(
            name: "CreatureTrunkFoundationTests",
            dependencies: ["CreatureTrunkFoundation"]
        ),
        .testTarget(
            name: "CreatureSnippetsTests",
            dependencies: ["CreatureSnippets"]
        ),
        // Tests for CLI-level wiring that dispatches across BOTH tentacles
        // (WorkspaceIndexer) — see CreatureCLI/WorkspaceIndexer.swift's doc
        // comment for why this lives in CreatureCLI rather than CreatureTrunk.
        .testTarget(
            name: "CreatureCLITests",
            dependencies: ["CreatureCLI", "CreatureChat", "CreatureWorkspace", "CreatureTrunk", "CreatureTrunkSwift"]
        )
    ]
)
