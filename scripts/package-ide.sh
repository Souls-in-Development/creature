#!/usr/bin/env bash
#
# Assemble Creature.app — the CreatureIDE executable as a real macOS app bundle.
#
# Usage: scripts/package-ide.sh [version]
#
# Produces dist/Creature.app (and, with --zip, a zipped, checksummed copy).
#
# WHY A BUNDLE, not just the executable:
# `swift build` / xcodebuild on the SPM scheme produce a bare Mach-O executable.
# Run directly, a SwiftUI app then launches as an *accessory* — no Dock icon, no
# menu bar, no reliable key window. A real .app with an Info.plist gets regular
# activation, an icon, and an identity. That is item 5 of the release plan.
#
# The metallib caveat from the CLI applies here too: the IDE runs models in-
# process (its chat pane drives CreatureChat), so the same resource bundles —
# including mlx-swift_Cmlx.bundle/…/default.metallib — must travel next to the
# executable, here inside Contents/MacOS. Bundle.module resolves relative to the
# executable, so this is the layout that lets the IDE actually generate.
#
# SIGNING: this ad-hoc signs (`codesign -s -`) so the bundle runs on THIS
# machine. That is NOT notarisation. A browser-downloaded .app is quarantined by
# LaunchServices, and clearing that needs a Developer ID Application certificate
# (paid Apple Developer Program) + notarisation — neither of which exists yet.
# Until then, a downloaded build opens via System Settings → Privacy & Security →
# Open Anyway (since macOS 15 it is no longer Control-click → Open).

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

VERSION_ARG="${1:-}"
DO_ZIP=0
for arg in "$@"; do
    [ "$arg" = "--zip" ] && DO_ZIP=1
done

DERIVED_DATA="${DERIVED_DATA:-$ROOT/.release-build}"
DIST="$ROOT/dist"
APP="$DIST/Creature.app"

log() { printf '\033[38;5;115m==>\033[0m %s\n' "$*"; }
die() { printf '\033[38;5;203merror:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "macOS only (got $(uname -s))"
[ "$(uname -m)" = "arm64" ] || die "Apple Silicon only; MLX has no Intel path"
command -v xcodebuild >/dev/null || die "xcodebuild not found — full Xcode is required"

log "building creature-ide (Release, xcodebuild)"
xcodebuild build \
    -scheme creature-ide \
    -destination 'platform=OS X' \
    -configuration Release \
    -skipMacroValidation \
    -derivedDataPath "$DERIVED_DATA" \
    >/dev/null || die "xcodebuild failed — re-run without >/dev/null to see why"

PRODUCTS="$DERIVED_DATA/Build/Products/Release"
[ -x "$PRODUCTS/creature-ide" ] || die "no creature-ide binary at $PRODUCTS/creature-ide"

# Version: the IDE has no --version, so take it from the CLI binary if it was
# built alongside (same DerivedData), else the argument, else 0.1.0. Keeps the
# app and CLI versions in lockstep when both are built from one release run.
VERSION="$VERSION_ARG"
if [ -z "$VERSION" ] && [ -x "$PRODUCTS/creature" ]; then
    VERSION="$("$PRODUCTS/creature" --version | awk '{print $2}')"
fi
VERSION="${VERSION:-0.1.0}"
log "version $VERSION"

log "assembling Creature.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$PRODUCTS/creature-ide" "$APP/Contents/MacOS/"

# Resource bundles next to the executable — the metallib among them.
bundle_count=0
for bundle in "$PRODUCTS"/*.bundle; do
    [ -e "$bundle" ] || continue
    cp -R "$bundle" "$APP/Contents/MacOS/"
    bundle_count=$((bundle_count + 1))
done
[ "$bundle_count" -gt 0 ] || die "no .bundle resources found — the IDE could not run a model"
[ -d "$APP/Contents/MacOS/mlx-swift_Cmlx.bundle" ] || die "mlx-swift_Cmlx.bundle missing — this app cannot generate"

cp "$ROOT/packaging/ide/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
sed "s/__VERSION__/$VERSION/g" "$ROOT/packaging/ide/Info.plist" > "$APP/Contents/Info.plist"

# PkgInfo is legacy but cheap and expected by some tooling.
printf 'APPL????' > "$APP/Contents/PkgInfo"

log "ad-hoc signing (runs locally; NOT notarised — see header)"
# Strip extended attributes first. Finder color tags (e.g. from the Atlas skill)
# and other xattrs on the source files get copied into the bundle and make
# codesign fail with "resource fork, Finder information, or similar detritus".
xattr -cr "$APP" 2>/dev/null || true
codesign --force --deep --sign - --identifier dev.soulsin.creature-ide "$APP" >/dev/null 2>&1 \
    || printf '\033[38;5;215mwarning:\033[0m ad-hoc codesign failed; the app may need a manual Gatekeeper override to launch.\n'

# Sanity: the bundle is well-formed enough for LaunchServices to read it.
/usr/bin/plutil -lint "$APP/Contents/Info.plist" >/dev/null || die "Info.plist failed plutil lint"

log "built $APP"

if [ "$DO_ZIP" = "1" ]; then
    ZIP="$DIST/Creature-$VERSION-macos-arm64.zip"
    rm -f "$ZIP" "$ZIP.sha256"
    # ditto preserves the bundle + code signature inside the zip.
    ( cd "$DIST" && ditto -c -k --sequesterRsrc --keepParent "Creature.app" "$ZIP" )
    ( cd "$DIST" && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256" )
    log "zipped $ZIP"
    printf '  sha256  %s\n' "$(awk '{print $1}' < "$ZIP.sha256")"
fi

printf '\nRun it:  open "%s"\n' "$APP"
