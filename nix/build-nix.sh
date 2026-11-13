#!/usr/bin/env bash
#
# build-nix.sh - one-click Nix build + redistributable tarball for Linux hosts
#
# The Nix flavour of android/build-module.sh: instead of cross-compiling the
# patched upstream tree with the Android NDK, build the very same tree
# (geph5 pinned by patches/BASE + the patches/ series, applied by the
# derivation itself) with `nix build .#geph5`, then copy the two binaries out
# of the closure into nix/dist/geph5-<version>-<arch>.tar.xz for deployment on
# non-Nix machines of a compatible distro generation — the role the Termux deb
# plays for Android. For NixOS hosts, use the flake directly instead of the
# tarball (`nix run`, `nix profile install`), which also links the runtime
# deps (openssl, glibc) correctly.
#
# Usage:
#   ./nix/build-nix.sh                  # nix build + package tarball
#   ./nix/build-nix.sh --skip-build     # reuse nix/result, repackage only
#   ./nix/build-nix.sh --out-dir DIR    # override nix/dist
#
# Requirements: nix with flakes (>= 2.4), network access to github.com for the
#               flake inputs and the pinned geph5 source, disk space for the
#               Rust build closure.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

die() { echo "error: $*" >&2; exit 1; }

# --- option parsing --------------------------------------------------------
SKIP_BUILD=0
OUT_DIR="$SCRIPT_DIR/dist"
while [ $# -gt 0 ]; do
  case "$1" in
    --skip-build) SKIP_BUILD=1 ;;
    --out-dir)
      [ $# -ge 2 ] || die "--out-dir requires a path argument"
      OUT_DIR="$2"; shift ;;
    -h|--help)
      sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
  shift
done

command -v nix >/dev/null 2>&1 \
  || die "nix not found in PATH (need nix with flakes for 'nix build .#geph5')"

# --- build -------------------------------------------------------------------
RESULT="$SCRIPT_DIR/result"
if [ "$SKIP_BUILD" -eq 0 ]; then
  echo "=== nix build .#geph5 ==="
  nix build "$REPO_ROOT#geph5" --out-link "$RESULT"
else
  [ -e "$RESULT/bin/geph5" ] \
    || die "--skip-build: $RESULT is missing its binaries; run without --skip-build first"
fi

for b in geph5 geph5-client; do
  [ -x "$RESULT/bin/$b" ] || die "build output incomplete: missing $RESULT/bin/$b"
done

# --- version + arch --------------------------------------------------------
VERSION="$("$RESULT/bin/geph5" --version 2>/dev/null | head -n1 | grep -oE '[0-9]+(\.[0-9]+)+' || true)"
[ -n "$VERSION" ] || VERSION="$(sed -n 's/^version = "\(.*\)"/\1/p' Cargo.toml | head -n1)"
[ -n "$VERSION" ] || die "could not determine a version for the tarball name"
ARCH="$(uname -m)"

# --- package -----------------------------------------------------------------
mkdir -p "$OUT_DIR"
TARBALL="$OUT_DIR/geph5-${VERSION}-${ARCH}.tar.xz"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/share/doc/geph5"
cp -a "$RESULT/bin/geph5" "$RESULT/bin/geph5-client" "$TMP/bin/"
cp "$SCRIPT_DIR/README.md" "$TMP/share/doc/geph5/README.nix.md"
tar -cJf "$TARBALL" -C "$TMP" .

# --- summary -----------------------------------------------------------------
sha() { sha256sum "$1" | awk '{print $1}'; }
echo
echo "=== geph5 built: nix closure + redistributable tarball ==="
echo "Closure: $RESULT"
echo "Tarball: $TARBALL ($(wc -c < "$TARBALL") bytes)"
echo "SHA256:  $(sha "$TARBALL")"
echo
echo "Note: the tarball binaries link against the build generation's glibc;"
echo "      on NixOS or with nix available, prefer the flake instead:"
echo "        nix run $REPO_ROOT#geph5 -- --help"
echo "        nix profile install $REPO_ROOT#geph5"
