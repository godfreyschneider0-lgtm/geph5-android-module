#!/usr/bin/env bash
#
# build-module.sh - one-click cross-compile + packaging for the geph5 KernelSU module.
#
# Cross-compiles geph5 and geph5-client for aarch64-linux-android using the Android
# NDK toolchain (API 24), stages the android/ksu/ template files together with the
# binaries, and packs everything into android/dist/geph5-ksu-<version>-arm64.zip.
# The zip root contains module.prop directly, ready for KernelSU.
#
# Usage:
#   ./android/build-module.sh [--skip-build] [--ndk <path>]
#
# Options:
#   --skip-build   Reuse existing release binaries under
#                  target/aarch64-linux-android/release/ (no cargo build).
#   --ndk <path>   Android NDK root. Default: $ANDROID_NDK_HOME, then
#                  $ANDROID_NDK_ROOT, then the newest version under
#                  $HOME/Android/Sdk/ndk/.
#
# Requirements: bash, cargo with rustup target aarch64-linux-android, git, zip,
#               an Android NDK with the aarch64-linux-android24 toolchain.
set -euo pipefail

# Resolve paths relative to this script so it works from any cwd.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

die() { echo "error: $*" >&2; exit 1; }

# --- option parsing --------------------------------------------------------
SKIP_BUILD=0
NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
while [ $# -gt 0 ]; do
  case "$1" in
    --skip-build) SKIP_BUILD=1 ;;
    --ndk)
      [ $# -ge 2 ] || die "--ndk requires a path argument"
      NDK="$2"; shift ;;
    -h|--help)
      sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
  shift
done

# --- NDK resolution --------------------------------------------------------
if [ -z "$NDK" ]; then
  NDK_ROOT="$HOME/Android/Sdk/ndk"
  [ -d "$NDK_ROOT" ] || die "no NDK found: pass --ndk, or set ANDROID_NDK_HOME/ANDROID_NDK_ROOT (looked in $NDK_ROOT)"
  NDK="$NDK_ROOT/$(ls -1 "$NDK_ROOT" | sort -V | tail -n1)"
fi
[ -d "$NDK" ] || die "NDK path does not exist: $NDK"

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)  HOST_TAG="linux-x86_64" ;;
  Darwin-x86_64) HOST_TAG="darwin-x86_64" ;;
  Linux-aarch64) HOST_TAG="linux-aarch64" ;;
  *) die "unsupported host: $(uname -s)-$(uname -m)" ;;
esac

TOOLBIN="$NDK/toolchains/llvm/prebuilt/$HOST_TAG/bin"
LINKER="$TOOLBIN/aarch64-linux-android24-clang"
[ -x "$LINKER" ] || die "NDK linker not found: $LINKER (invalid NDK or missing $HOST_TAG prebuilt)"

# Rust cross-compile environment for aarch64-linux-android (API 24).
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$LINKER"
export AR_aarch64_linux_android="$TOOLBIN/llvm-ar"
export CC_aarch64_linux_android="$LINKER"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_AR="$TOOLBIN/llvm-ar"

# --- version info ----------------------------------------------------------
VERSION="$(sed -n 's/^version = "\(.*\)"/\1/p' Cargo.toml | head -n1)"
[ -n "$VERSION" ] || die "could not read workspace version from Cargo.toml"
VERSION="v$VERSION"
VERSIONCODE="$(git rev-list --count HEAD 2>/dev/null || date +%Y%m%d)"

RELDIR="target/aarch64-linux-android/release"
BIN_GEPH5="$RELDIR/geph5"
BIN_CLIENT="$RELDIR/geph5-client"

# --- build -----------------------------------------------------------------
if [ "$SKIP_BUILD" -eq 1 ]; then
  [ -f "$BIN_GEPH5" ] && [ -f "$BIN_CLIENT" ] \
    || die "--skip-build: missing binaries (expected $BIN_GEPH5 and $BIN_CLIENT); run without --skip-build first"
  echo "skip-build: reusing existing binaries in $RELDIR"
else
  cargo build --release --target aarch64-linux-android -p geph5-app -p geph5-client
fi
[ -f "$BIN_GEPH5" ] && [ -f "$BIN_CLIENT" ] \
  || die "build produced no binaries; expected $BIN_GEPH5 and $BIN_CLIENT"

# --- stage -----------------------------------------------------------------
KSU_DIR="android/ksu"
DIST="android/dist"
STAGE="$DIST/stage"
[ -d "$KSU_DIR" ] || die "module template directory missing: $KSU_DIR"
rm -rf "$STAGE"
mkdir -p "$STAGE"

for f in module.prop service.sh action.sh uninstall.sh customize.sh README.md; do
  [ -f "$KSU_DIR/$f" ] || die "missing template file: $KSU_DIR/$f"
  cp "$KSU_DIR/$f" "$STAGE/$f"
done

sed -i -e "s|@@VERSION@@|$VERSION|g" -e "s|@@VERSIONCODE@@|$VERSIONCODE|g" "$STAGE/module.prop"

cp "$BIN_GEPH5" "$STAGE/geph5"
cp "$BIN_CLIENT" "$STAGE/geph5-client"
chmod 0755 "$STAGE/geph5" "$STAGE/geph5-client"

# Best-effort strip; ship unstripped if it fails.
if [ -x "$TOOLBIN/llvm-strip" ]; then
  "$TOOLBIN/llvm-strip" "$STAGE/geph5" "$STAGE/geph5-client" \
    || echo "warning: llvm-strip failed; shipping unstripped binaries" >&2
else
  echo "warning: llvm-strip not found in $TOOLBIN; shipping unstripped binaries" >&2
fi

# --- zip -------------------------------------------------------------------
ZIP="$DIST/geph5-ksu-${VERSION}-arm64.zip"
rm -f "$ZIP"
(cd "$STAGE" && zip -r9 -q "../$(basename "$ZIP")" .)

# --- summary ----------------------------------------------------------------
bytes() { wc -c < "$1"; }
if command -v sha256sum >/dev/null 2>&1; then
  ZIP_SHA="$(sha256sum "$ZIP" | awk '{print $1}')"
else
  ZIP_SHA="$(shasum -a 256 "$ZIP" | awk '{print $NF}')"
fi

echo
echo "=== geph5 KernelSU module built ==="
echo "Zip:     $ZIP ($(bytes "$ZIP") bytes)"
echo "SHA256:  $ZIP_SHA"
echo "geph5:       $(bytes "$BIN_GEPH5") bytes"
echo "geph5-client: $(bytes "$BIN_CLIENT") bytes"
echo
echo "Next steps:"
echo "  1. ADB:          ./android/install.sh $ZIP"
echo "  2. KernelSU app: KernelSU manager -> Install from storage -> $ZIP"
