#!/usr/bin/env bash
#
# Build a runnable creature. One command.
#
#   ./build.sh
#   ./bin/creature local "hello"
#
# WHY THIS EXISTS (read if you were about to run `swift build`):
# `swift build` compiles and passes tests, but produces a binary that CANNOT run
# a model. MLX runs on Metal, and SwiftPM on the command line cannot compile
# Metal shaders — only an Xcode build emits `default.metallib`. A `swift build`
# binary therefore dies on first generation with:
#
#     MLX error: Failed to load the default metallib
#
# This script does the Xcode build and puts the binary next to the resource
# bundles it needs (the metallib among them), so the result actually runs.
#
# Use `swift build` / `swift test` freely for compiling and testing — just not
# for a binary you intend to RUN.

set -euo pipefail

cd "$(dirname "$0")"
ROOT="$PWD"
DERIVED_DATA="${DERIVED_DATA:-$ROOT/.release-build}"
OUT="$ROOT/bin"

log()  { printf '\033[38;5;115m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[38;5;215mwarning:\033[0m %s\n' "$*"; }
die()  { printf '\033[38;5;203merror:\033[0m %s\n' "$*" >&2; exit 1; }

# --- preflight: fail early and clearly, not 3 minutes into a build ----------

[ "$(uname -s)" = "Darwin" ] || die "macOS only (this is $(uname -s))."

if [ "$(uname -m)" != "arm64" ]; then
    die "Apple Silicon required.
       creature runs models in-process via MLX, which is Metal-only. There is
       no Intel build and no workaround on this machine."
fi

# Capture first, then parse with parameter expansion. Piping into an early-exiting
# reader (head/cut) under `set -o pipefail` makes the producer die of SIGPIPE and
# aborts this script with no output — timing-dependent, so it "works" some runs.
MACOS_VERSION="$(sw_vers -productVersion)"
MACOS_MAJOR="${MACOS_VERSION%%.*}"
[ "$MACOS_MAJOR" -ge 14 ] || die "macOS 14 or newer required (this is $MACOS_VERSION)."

command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild not found.
       You need FULL Xcode, not just the Command Line Tools:
         https://apps.apple.com/app/xcode/id497799835
       Then: sudo xcode-select -s /Applications/Xcode.app"

# `xcode-select -p` pointing at CommandLineTools means xcodebuild exists but
# cannot build — catch that here rather than in a wall of build errors.
XCODE_PATH="$(xcode-select -p 2>/dev/null || echo '')"
case "$XCODE_PATH" in
    *CommandLineTools*)
        die "xcode-select points at the Command Line Tools, not Xcode:
       $XCODE_PATH
       Fix: sudo xcode-select -s /Applications/Xcode.app"
        ;;
esac

# Same SIGPIPE hazard as above — capture the whole output, then take line 1.
XCODEBUILD_VERSION_OUTPUT="$(xcodebuild -version 2>/dev/null || true)"
XCODE_VERSION_LINE="${XCODEBUILD_VERSION_OUTPUT%%$'\n'*}"
XCODE_VERSION="${XCODE_VERSION_LINE#Xcode }"
XCODE_MAJOR="${XCODE_VERSION%%.*}"
if [ -n "$XCODE_MAJOR" ] && [ "$XCODE_MAJOR" -lt 26 ] 2>/dev/null; then
    warn "Xcode $XCODE_VERSION found; this package targets the macOS 26 SDK (Xcode 26+). Build may fail."
fi

# --- build ------------------------------------------------------------------

log "building creature (Release, Xcode $XCODE_VERSION) — first build takes a few minutes"
xcodebuild build \
    -scheme creature \
    -destination 'platform=OS X' \
    -configuration Release \
    -skipMacroValidation \
    -derivedDataPath "$DERIVED_DATA" \
    >/dev/null 2>&1 || die "build failed. Re-run without output suppression to see why:
       xcodebuild build -scheme creature -destination 'platform=OS X' -configuration Release -skipMacroValidation -derivedDataPath '$DERIVED_DATA'"

PRODUCTS="$DERIVED_DATA/Build/Products/Release"
[ -x "$PRODUCTS/creature" ] || die "no binary produced at $PRODUCTS/creature"

# --- assemble a runnable layout --------------------------------------------
# The binary resolves its resources (Bundle.module) relative to itself, so every
# .bundle must sit beside it — mlx-swift_Cmlx.bundle carries default.metallib.

log "assembling ./bin"
rm -rf "$OUT"
mkdir -p "$OUT"
cp "$PRODUCTS/creature" "$OUT/"
for bundle in "$PRODUCTS"/*.bundle; do
    [ -e "$bundle" ] || continue
    cp -R "$bundle" "$OUT/"
done

[ -d "$OUT/mlx-swift_Cmlx.bundle" ] || die "mlx-swift_Cmlx.bundle missing — the binary could not run a model."

# --- verify it can actually generate ---------------------------------------
# Proving it RUNS is the whole point of this script; linking is not enough.
# Skipped automatically when no model is cached yet (that would force a ~1.6 GB
# download just to validate the build).

HF_CACHE="${HF_HOME:-$HOME/.cache/huggingface}"
if [ -d "$HF_CACHE" ] && [ -n "$(find "$HF_CACHE" -name '*.safetensors' -print -quit 2>/dev/null)" ]; then
    log "verifying it can generate"
    if (cd "$OUT" && ./creature local "say ok" >/dev/null 2>&1); then
        log "  generated successfully"
    else
        warn "the binary did not generate. Run: ./bin/creature local \"hello\" to see the error."
    fi
else
    log "skipping generation check (no model cached yet — first run will download ~1.6 GB)"
fi

printf '\n\033[38;5;115mReady.\033[0m Run it:\n\n    ./bin/creature local "hello"\n    ./bin/creature chat\n\n'
printf 'First run downloads the default model (~1.6 GB) to ~/.cache/huggingface.\n'
