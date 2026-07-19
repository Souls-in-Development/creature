import Foundation

/// Whether this build can actually run a model, and what to do when it can't.
///
/// MLX runs on Metal, and its shader library (`default.metallib`) is emitted only
/// by an **Xcode** build — SwiftPM on the command line cannot compile Metal
/// shaders (a documented mlx-swift limitation). So `swift build` yields a binary
/// that compiles, links, and passes tests, then dies the moment it generates:
///
///     MLX error: Failed to load the default metallib
///
/// That abort happens deep in C++ and cannot be caught. So detect the missing
/// library *first* and fail with an instruction instead of a stack trace.
public enum InferenceRuntime {

    /// The resource bundle MLX ships its compiled Metal shaders in. It must sit
    /// next to the executable for `Bundle.module` to resolve it.
    private static let metallibBundleName = "mlx-swift_Cmlx.bundle"

    /// True when the Metal shader library is present next to this executable —
    /// i.e. this binary can actually run a model.
    public static var isMetalLibraryAvailable: Bool {
        guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() else {
            return false
        }
        let metallib = executable
            .deletingLastPathComponent()
            .appendingPathComponent(metallibBundleName)
            .appendingPathComponent("Contents/Resources/default.metallib")
        return FileManager.default.fileExists(atPath: metallib.path)
    }

    /// Exactly what to do about it. Written to be actionable on first read — the
    /// person hitting this is usually someone who just cloned the repo and ran
    /// the obvious command.
    public static var missingRuntimeGuidance: String {
        """
        This build cannot run a model — MLX's Metal shader library is missing.

        Why: `swift build` cannot compile Metal shaders (an mlx-swift limitation),
        so it produces a binary that links but cannot generate.

        Fix — build with Xcode instead (one command, from the repo root):

            ./build.sh

        That produces a runnable binary at ./bin/creature. Then:

            ./bin/creature local "hello"

        Requires full Xcode (not just Command Line Tools), Apple Silicon, macOS 14+.
        """
    }
}
