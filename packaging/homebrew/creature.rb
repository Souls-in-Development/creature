# Homebrew formula for the creature CLI.
#
# This file is the canonical copy. It is published to the tap repo
# (Souls-in-Development/homebrew-tap) as Formula/creature.rb — by .github/workflows/release.yml
# on tag, or by hand. Edit it here, not there.
#
# WHY THIS SHIPS A PRE-BUILT BINARY, against Homebrew's build-from-source grain:
# MLX-Swift's Metal shaders cannot be compiled by SwiftPM on the command line
# (documented upstream). A source build therefore needs *full Xcode* — not the
# Command Line Tools that `brew install` can assume — so building from source
# here would fail for most users, and fail late, at first generation, with
# "Failed to load the default metallib". Shipping the Xcode-built artifact is
# the honest option. See scripts/package-release.sh.
class Creature < Formula
  desc "Living terminal that runs its own model"
  homepage "https://soulsin.dev"
  url "https://github.com/Souls-in-Development/creature/releases/download/v0.1.0/creature-0.1.0-macos-arm64.tar.gz"
  version "0.1.0"
  sha256 "f7e36fb9a570c33f9719d4da573ce70c4afd97c0eab97b3f26a4cd70c722cd96"
  license "AGPL-3.0-only"

  # MLX runs on Metal. There is no Intel path, and the binary is arm64-only, so
  # refuse the install outright rather than let an Intel user discover it at
  # first generation. `depends_on macos:` is a minimum (>=), not an equality.
  depends_on arch: :arm64
  depends_on macos: :sonoma

  def install
    # NOT `bin.install "creature"`. The binary resolves its resources
    # (Bundle.module) relative to its own location, and mlx-swift_Cmlx.bundle
    # carries default.metallib. A lone binary in bin/ cannot find it and dies on
    # the first generation. Keep the payload together in libexec.
    libexec.install "creature"
    libexec.install Dir["*.bundle"]

    # AND NOT `bin.install_symlink` either. MLX resolves the metallib from the
    # executable path WITHOUT resolving symlinks, so through a symlink it looks
    # in bin/ — where there are no bundles — and dies with a bare
    # "Failed to load the default metallib". An exec script is the fix: the
    # process that ends up running is the real libexec binary, so the lookup
    # starts in the right directory.
    #
    # Measured on 0.1.0, brew-installed: direct libexec path generates; the
    # same build through the symlink fails. `--version` works either way, which
    # is exactly why the test block below is not sufficient on its own.
    bin.write_exec_script libexec/"creature"

    prefix.install "LICENSE"
    doc.install "README.md"
  end

  def caveats
    <<~EOS
      creature runs models in-process. The default soul
      (mlx-community/Qwen2.5-3B-Instruct-4bit, ~1.6 GB) is downloaded on first use
      and cached in ~/.cache/huggingface:

        creature local "hello"

      To use your own models or a remote OpenAI-compatible endpoint instead:

        creature config
    EOS
  end

  test do
    assert_match "creature #{version}", shell_output("#{bin}/creature --version")

    # Assert the payload that makes generation possible actually landed. The
    # metallib is the thing most likely to be silently dropped by a packaging
    # change, and its absence is invisible until someone runs a model.
    assert_path_exists libexec/"mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"

    # Present is not the same as reachable. 0.1.0 shipped with the metallib in
    # the right place and still could not load it, because bin/creature was a
    # symlink and MLX does not resolve those before looking for its bundles.
    # Assert the exec-script shape that fixes it — running a model here would
    # need a GPU and a 1.6 GB download, so this is the most the test block can
    # honestly check.
    refute_predicate bin/"creature", :symlink?
    assert_match libexec.to_s, (bin/"creature").read
  end
end
