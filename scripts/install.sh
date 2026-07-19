#!/bin/sh
#
# creature installer — https://soulsin.dev
#
#   curl -fsSL https://soulsin.dev/install.sh | sh
#
# Environment:
#   CREATURE_VERSION   pin a version (default: latest release)
#   CREATURE_PREFIX    install prefix (default: /usr/local)
#
# Deliberately POSIX sh: this is piped into whatever /bin/sh is, so it cannot
# assume bash. No pipefail, no arrays, no [[.
#
# Note on Gatekeeper: neither curl nor brew sets com.apple.quarantine, so a CLI
# installed this way raises no security prompt. That is NOT true of a .app
# downloaded in a browser — see the IDE's own packaging when it exists.

set -eu

REPO="Souls-in-Development/creature"
PREFIX="${CREATURE_PREFIX:-/usr/local}"
VERSION="${CREATURE_VERSION:-}"

# Colours only when attached to a terminal — piped installs get plain text.
if [ -t 1 ]; then
    C_ACCENT="$(printf '\033[38;5;115m')"; C_DIM="$(printf '\033[38;5;243m')"
    C_ERR="$(printf '\033[38;5;203m')"; C_OFF="$(printf '\033[0m')"
else
    C_ACCENT=""; C_DIM=""; C_ERR=""; C_OFF=""
fi

log() { printf '%s==>%s %s\n' "$C_ACCENT" "$C_OFF" "$*"; }
dim() { printf '%s    %s%s\n' "$C_DIM" "$*" "$C_OFF"; }
die() { printf '%serror:%s %s\n' "$C_ERR" "$C_OFF" "$*" >&2; exit 1; }

# --- preflight -------------------------------------------------------------
# Fail here, with a reason, rather than after a 13 MB download.

[ "$(uname -s)" = "Darwin" ] || die "creature is macOS-only (this is $(uname -s))."

if [ "$(uname -m)" != "arm64" ]; then
    die "creature requires Apple Silicon.
       It runs models in-process via MLX, which is Metal-only — there is no
       Intel build, and there is no workaround on this machine."
fi

MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$MACOS_MAJOR" -lt 14 ]; then
    die "creature requires macOS 14 or newer (this is $(sw_vers -productVersion))."
fi

command -v curl >/dev/null 2>&1 || die "curl is required."
command -v shasum >/dev/null 2>&1 || die "shasum is required."

# --- resolve version -------------------------------------------------------

if [ -z "$VERSION" ]; then
    log "finding the latest release"
    VERSION="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
        | sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' \
        | head -1)"
    [ -n "$VERSION" ] || die "could not determine the latest version.
       Set one explicitly:  CREATURE_VERSION=0.1.0 sh install.sh"
fi
VERSION="${VERSION#v}"

NAME="creature-$VERSION-macos-arm64"
URL="https://github.com/$REPO/releases/download/v$VERSION/$NAME.tar.gz"

# --- download + verify -----------------------------------------------------

TMP="$(mktemp -d)"
# Clean up on any exit path, including the checksum failure below.
trap 'rm -rf "$TMP"' EXIT INT TERM

log "downloading creature $VERSION"
dim "$URL"
curl -fsSL "$URL" -o "$TMP/$NAME.tar.gz" \
    || die "download failed. Is $VERSION a real release? See https://github.com/$REPO/releases"
curl -fsSL "$URL.sha256" -o "$TMP/$NAME.tar.gz.sha256" \
    || die "could not fetch the checksum for $VERSION. Refusing to install unverified."

log "verifying checksum"
EXPECTED="$(awk '{print $1}' < "$TMP/$NAME.tar.gz.sha256")"
ACTUAL="$(shasum -a 256 "$TMP/$NAME.tar.gz" | awk '{print $1}')"
if [ "$EXPECTED" != "$ACTUAL" ]; then
    die "checksum mismatch — NOT installing.
       expected  $EXPECTED
       actual    $ACTUAL
       The download is corrupt or has been tampered with. Please report this."
fi
dim "sha256 ok"

# --- install ---------------------------------------------------------------

tar -xzf "$TMP/$NAME.tar.gz" -C "$TMP" || die "could not extract the archive."
[ -x "$TMP/$NAME/creature" ] || die "archive did not contain a creature binary."

# The binary resolves its resource bundles (including the metallib that makes
# generation possible) relative to itself, so the payload is installed whole
# into libexec — never copy the binary alone.
#
# It is exposed through an exec script, NOT a symlink. MLX looks for its
# bundles next to the executable path without resolving symlinks first, so a
# symlinked bin/creature searches bin/ (no bundles there) and dies on the first
# generation with a bare "Failed to load the default metallib". `--version`
# still works through a symlink, which is what makes this so easy to ship
# broken — it was, in 0.1.0.
LIBEXEC="$PREFIX/libexec/creature"
BINDIR="$PREFIX/bin"

SUDO=""
if [ ! -w "$PREFIX" ] || { [ -e "$BINDIR" ] && [ ! -w "$BINDIR" ]; }; then
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
        log "$PREFIX needs administrator access"
        dim "installing with sudo — you may be prompted for your password"
        dim "to avoid this:  CREATURE_PREFIX=\$HOME/.local sh install.sh"
    else
        die "$PREFIX is not writable and sudo is unavailable.
       Try:  CREATURE_PREFIX=\$HOME/.local sh install.sh"
    fi
fi

log "installing to $PREFIX"
$SUDO mkdir -p "$LIBEXEC" "$BINDIR" || die "could not create $LIBEXEC"
$SUDO rm -rf "${LIBEXEC:?}/"* 2>/dev/null || true
$SUDO cp -R "$TMP/$NAME/"* "$LIBEXEC/" || die "could not copy files into $LIBEXEC"
printf '#!/bin/sh\nexec "%s/creature" "$@"\n' "$LIBEXEC" > "$TMP/creature-exec"
$SUDO cp "$TMP/creature-exec" "$BINDIR/creature" || die "could not write $BINDIR/creature"
$SUDO chmod 755 "$BINDIR/creature" || die "could not make $BINDIR/creature executable"

# --- report ----------------------------------------------------------------

log "creature $VERSION installed"

INSTALLED_VERSION="$("$BINDIR/creature" --version 2>/dev/null || true)"
[ -n "$INSTALLED_VERSION" ] || die "installed, but '$BINDIR/creature --version' did not run.
       Something is wrong with the payload — please report this."
dim "$INSTALLED_VERSION"

# Tell the truth about PATH rather than assuming the prefix is on it.
case ":$PATH:" in
    *":$BINDIR:"*) ;;
    *)
        printf '\n%s%s is not on your PATH.%s Add this to your shell profile:\n\n' \
            "$C_ERR" "$BINDIR" "$C_OFF"
        # $PATH must appear literally in the line the user copies into their
        # profile — expanding it here would be wrong.
        # shellcheck disable=SC2016
        printf '    export PATH="%s:$PATH"\n' "$BINDIR"
        ;;
esac

printf '\nThe creature runs its own model. On first use it downloads the default\nsoul (~1.6 GB) into ~/.cache/huggingface:\n\n'
printf '    creature local "hello"\n\n'
printf 'To use your own models, or a remote OpenAI-compatible endpoint:\n\n'
printf '    creature config\n\n'
printf '%ssoulsin.dev%s\n' "$C_DIM" "$C_OFF"
