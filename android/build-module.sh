#!/usr/bin/env bash
#
# build-module.sh - one-click cross-compile + packaging for the geph5 KernelSU module.
#
# Cross-compiles geph5 and geph5-client for aarch64-linux-android (arm64) and
# x86_64-linux-android (x64) using the Android NDK toolchain (API 24), stages
# the android/ksu/ template files together with the binaries, and packs each
# into android/dist/geph5-ksu-<version>-<arch>.zip. Each zip root contains
# module.prop directly, ready for KernelSU.
#
# Usage:
#   ./android/build-module.sh [--skip-build] [--ndk <path>] [--arch all|arm64|x64]
#
# Options:
#   --skip-build   Reuse existing release binaries (no cargo build). Requires
#                  binaries already present for every requested arch.
#   --ndk <path>   Android NDK root. Default: $ANDROID_NDK_HOME, then
#                  $ANDROID_NDK_ROOT, then the newest version under
#                  $HOME/Android/Sdk/ndk/.
#   --arch <sel>   Which arches to build: all (default), arm64, or x64.
#
# Requirements: bash, cargo with rustup targets aarch64-linux-android and
#               x86_64-linux-android, git, zip, an Android NDK with the
#               <arch>-linux-android24 toolchains.
set -euo pipefail

# Resolve paths relative to this script so it works from any cwd.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

die() { echo "error: $*" >&2; exit 1; }

# --- option parsing --------------------------------------------------------
SKIP_BUILD=0
NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
ARCHS="all"
while [ $# -gt 0 ]; do
  case "$1" in
    --skip-build) SKIP_BUILD=1 ;;
    --ndk)
      [ $# -ge 2 ] || die "--ndk requires a path argument"
      NDK="$2"; shift ;;
    --arch)
      [ $# -ge 2 ] || die "--arch requires an argument (all|arm64|x64)"
      ARCHS="$2"; shift ;;
    -h|--help)
      sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
  shift
done

case "$ARCHS" in
  all)  BUILD_LIST="arm64 x64" ;;
  arm64) BUILD_LIST="arm64" ;;
  x64)  BUILD_LIST="x64" ;;
  *) die "invalid --arch: $ARCHS (expected all|arm64|x64)" ;;
esac

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
[ -d "$TOOLBIN" ] || die "NDK prebuilt toolchain dir not found: $TOOLBIN"

# --- version info ----------------------------------------------------------
VERSION="$(sed -n 's/^version = "\(.*\)"/\1/p' Cargo.toml | head -n1)"
[ -n "$VERSION" ] || die "could not read workspace version from Cargo.toml"
VERSION="v$VERSION"
VERSIONCODE="$(git rev-list --count HEAD 2>/dev/null || date +%Y%m%d)"

# arch -> rust target, zip arch label
arm64() { TARGET=aarch64-linux-android; ZLAB=arm64; }
x64()   { TARGET=x86_64-linux-android;   ZLAB=x64;   }

build_one() {
  eval "$1"
  LINKER="$TOOLBIN/${TARGET}24-clang"
  [ -x "$LINKER" ] || die "NDK linker not found: $LINKER"

  # Rust cross-compile environment for <target> (API 24). cargo uses the
  # UPPERCASE underscore target for CARGO_TARGET_*_LINKER; cc-rs uses the
  # lowercase form for CC_*/AR_*.
  TUVAR="${TARGET//-/_}"
  TUVAR_UP="${TUVAR^^}"
  export "CARGO_TARGET_${TUVAR_UP}_LINKER=$LINKER"
  export "CC_${TUVAR}=$LINKER"
  export "AR_${TUVAR}=$TOOLBIN/llvm-ar"

  RELDIR="target/$TARGET/release"
  BIN_GEPH5="$RELDIR/geph5"
  BIN_CLIENT="$RELDIR/geph5-client"

  # --- build ---------------------------------------------------------------
  if [ "$SKIP_BUILD" -eq 1 ]; then
    [ -f "$BIN_GEPH5" ] && [ -f "$BIN_CLIENT" ] \
      || die "--skip-build: missing binaries (expected $BIN_GEPH5 and $BIN_CLIENT); run without --skip-build first"
    echo "skip-build: reusing existing binaries in $RELDIR" >&2
  else
    cargo build --release --target "$TARGET" -p geph5-app -p geph5-client
  fi
  [ -f "$BIN_GEPH5" ] && [ -f "$BIN_CLIENT" ] \
    || die "build produced no binaries; expected $BIN_GEPH5 and $BIN_CLIENT"

  # --- stage ---------------------------------------------------------------
  KSU_DIR="android/ksu"
  DIST="android/dist"
  STAGE="$DIST/stage-$ZLAB"
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

  # Include the Termux control wrapper so the installer can deploy it at flash
  # time to $PREFIX/bin/gephctl (or /data/local/tmp as a fallback).
  cp "$SCRIPT_DIR/termux-gephctl.sh" "$STAGE/gephctl"
  chmod 0755 "$STAGE/gephctl"

  # Best-effort strip; ship unstripped if it fails.
  if [ -x "$TOOLBIN/llvm-strip" ]; then
    "$TOOLBIN/llvm-strip" "$STAGE/geph5" "$STAGE/geph5-client" \
      || echo "warning: llvm-strip failed; shipping unstripped binaries" >&2
  else
    echo "warning: llvm-strip not found in $TOOLBIN; shipping unstripped binaries" >&2
  fi

  # --- zip -----------------------------------------------------------------
  ZIP="$DIST/geph5-ksu-${VERSION}-$ZLAB.zip"
  rm -f "$ZIP"
  (cd "$STAGE" && zip -r9 -q "../$(basename "$ZIP")" .)
  echo "$ZIP"
}

echo "Building arches: $BUILD_LIST"
ZIPS=""
for a in $BUILD_LIST; do
  echo "=== building $a ==="
  ZIP="$(build_one "$a")"
  ZIPS="$ZIPS $ZIP"
done

# --- summary ----------------------------------------------------------------
bytes() { wc -c < "$1"; }
sha() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $NF}'
  fi
}

echo
echo "=== geph5 KernelSU modules built ==="
for z in $ZIPS; do
  echo "Zip:     $z ($(bytes "$z") bytes)"
  echo "SHA256:  $(sha "$z")"
done
echo
echo "Next steps:"
echo "  1. ADB:          ./android/install.sh android/dist/geph5-ksu-${VERSION}-<arch>.zip"
echo "  2. KernelSU app: KernelSU manager -> Install from storage -> pick the matching arch zip"
