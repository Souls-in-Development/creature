#!/usr/bin/env bash
#
# Build and package a release tarball of the creature CLI.
#
# Usage: scripts/package-release.sh [version]
#
# Produces, in dist/:
#   creature-<version>-macos-arm64.tar.gz
#   creature-<version>-macos-arm64.tar.gz.sha256
#
# WHY xcodebuild AND NOT `swift build -c release`:
# MLX-Swift's Metal shaders cannot be compiled by SwiftPM on the command line
# (documented upstream in mlx-swift's README). `swift build` links and passes
# tests, but the binary it produces dies the moment it tries to generate:
#
#     MLX error: Failed to load the default metallib
#
# because no default.metallib is emitted. Only an Xcode build produces
# mlx-swift_Cmlx.bundle. This is also why the tap ships a pre-built binary
# rather than building from source: a source build would require every user to
# have full Xcode, not just the Command Line Tools.
#
# The payload is therefore NOT just an executable. `creature` resolves its
# resources (Bundle.module) relative to the executable, so every .bundle must
# travel next to the binary. Dropping mlx-swift_Cmlx.bundle reproduces the
# metallib error above.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

VERSION="${1:-}"
DERIVED_DATA="${DERIVED_DATA:-$ROOT/.release-build}"
DIST="$ROOT/dist"
STAGE_NAME=""

log() { printf '\033[38;5;115m==>\033[0m %s\n' "$*"; }
die() { printf '\033[38;5;203merror:\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "release builds are macOS-only (got $(uname -s))"
[[ "$(uname -m)" == "arm64" ]] || die "release builds require Apple Silicon; MLX has no Intel path"
command -v xcodebuild >/dev/null || die "xcodebuild not found — full Xcode is required, not just Command Line Tools"

log "building creature (Release, xcodebuild)"
xcodebuild build \
    -scheme creature \
    -destination 'platform=OS X' \
    -configuration Release \
    -skipMacroValidation \
    -derivedDataPath "$DERIVED_DATA" \
    >/dev/null || die "xcodebuild failed — re-run without >/dev/null to see why"

PRODUCTS="$DERIVED_DATA/Build/Products/Release"
[[ -x "$PRODUCTS/creature" ]] || die "no creature binary at $PRODUCTS/creature"

# Take the version from the binary itself rather than trusting the argument, so
# a forgotten bump in main.swift cannot ship as the wrong tag.
BINARY_VERSION="$("$PRODUCTS/creature" --version | awk '{print $2}')"
[[ -n "$BINARY_VERSION" ]] || die "could not read version from creature --version"

if [[ -z "$VERSION" ]]; then
    VERSION="$BINARY_VERSION"
    log "version $VERSION (from binary)"
elif [[ "$VERSION" != "$BINARY_VERSION" ]]; then
    die "version mismatch: asked for $VERSION but the binary reports $BINARY_VERSION.
       Bump the version in Sources/CreatureCLI/main.swift and rebuild."
fi

STAGE_NAME="creature-$VERSION-macos-arm64"
STAGE="$DIST/$STAGE_NAME"
rm -rf "$STAGE"
mkdir -p "$STAGE"

log "staging payload"
cp "$PRODUCTS/creature" "$STAGE/"

# Every resource bundle, not a hand-picked subset: the set is decided by the
# dependency graph, so hardcoding names here would silently drop a bundle the
# next dependency bump introduces.
bundle_count=0
for bundle in "$PRODUCTS"/*.bundle; do
    [[ -e "$bundle" ]] || continue
    cp -R "$bundle" "$STAGE/"
    bundle_count=$((bundle_count + 1))
done
[[ "$bundle_count" -gt 0 ]] || die "no .bundle resources found in $PRODUCTS — the binary would fail to load its metallib"
[[ -d "$STAGE/mlx-swift_Cmlx.bundle" ]] || die "mlx-swift_Cmlx.bundle missing — this payload cannot run a model"

# AGPLv3 §4 requires the licence to travel with the binary.
cp "$ROOT/LICENSE" "$STAGE/"
cp "$ROOT/README.md" "$STAGE/"

log "verifying the staged payload can actually generate"
# Proves the packaged artifact runs a model, not merely that it linked. This is
# the whole point: `swift build` also "succeeds" and produces a broken binary.
if [[ -n "${SKIP_INFERENCE_CHECK:-}" ]]; then
    log "  skipped (SKIP_INFERENCE_CHECK set)"
elif ! (cd "$STAGE" && ./creature local "hi" >/dev/null 2>&1); then
    die "the staged binary failed to generate. The payload is broken — refusing to ship it.
       Re-run: (cd '$STAGE' && ./creature local hi) to see the failure.
       Set SKIP_INFERENCE_CHECK=1 to package anyway (e.g. no model cached in CI)."
else
    log "  generated successfully"
fi

log "creating tarball"
TARBALL="$DIST/$STAGE_NAME.tar.gz"
rm -f "$TARBALL" "$TARBALL.sha256"
# COPYFILE_DISABLE stops macOS tar from embedding ._* AppleDouble files, which
# would change the checksum between machines.
COPYFILE_DISABLE=1 tar -czf "$TARBALL" -C "$DIST" "$STAGE_NAME"
rm -rf "$STAGE"

( cd "$DIST" && shasum -a 256 "$STAGE_NAME.tar.gz" > "$STAGE_NAME.tar.gz.sha256" )

SHA="$(awk '{print $1}' < "$TARBALL.sha256")"
SIZE="$(du -h "$TARBALL" | awk '{print $1}')"

log "done"
printf '\n  %s\n  %s  %s\n  sha256  %s\n\n' "$TARBALL" "size" "$SIZE" "$SHA"
printf 'Next: update the formula in the tap with this url + sha256.\n'
