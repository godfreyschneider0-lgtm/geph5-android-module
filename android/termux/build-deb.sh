#!/data/data/com.termux/files/usr/bin/bash
#
# build-deb.sh - build the geph5 Termux .deb package (on-device).
#
# Produces android/dist/geph5_<version>_<arch>.deb, installable with
#   pkg install ./geph5_<version>_<arch>.deb
# Dependencies (termux-services) are resolved by apt automatically.
#
# Usage:
#   ./android/termux/build-deb.sh [--skip-build]
#
# The Rust source is the upstream/ pristine clone; this script applies patches/ to
# it before building (same as android/build-module.sh), so a plain checkout
# of this repo builds without any manual preparation step.
#
# The deb ships:
#   $PREFIX/bin/{geph5,geph5-client,gephsvc}
#   $PREFIX/sv/geph5/{run,log/run}        (termux-services supervision)
#   $PREFIX/share/doc/geph5/README.md
# plus DEBIAN/{control,postinst,prerm,postrm} maintainer scripts
# (seed settings.json with Termux ports, enable + start the service).
#
# Requirements: Termux, cargo (pkg install rust), dpkg (pkg install dpkg).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

SKIP_BUILD=0
[ "${1:-}" = "--skip-build" ] && SKIP_BUILD=1

# --- upstream workspace ----------------------------------------------------
# Same contract as android/build-module.sh: never build an unpatched tree.
WORKSPACE="$REPO_ROOT/upstream"
# upstream/ is a plain, gitignored pristine clone pinned by patches/BASE (not
# a submodule). Bootstrap it on first use; git honours https_proxy if set.
if [ ! -f "$WORKSPACE/Cargo.toml" ]; then
  echo "=== bootstrapping upstream/ (pristine clone at patches/BASE) ==="
  git clone https://github.com/geph-official/geph5.git "$WORKSPACE" \
    || die "could not clone geph5 into $WORKSPACE (set https_proxy if censored)"
  git -C "$WORKSPACE" checkout --quiet "$(cat "$REPO_ROOT/patches/BASE")" \
    || die "could not pin upstream/ to patches/BASE"
fi
if [ "$SKIP_BUILD" -eq 1 ]; then
  bash "$REPO_ROOT/apply-patches.sh" --check "$WORKSPACE" \
    || die "patch series does not apply to upstream/ (--skip-build was given)"
else
  echo "=== applying patch series to upstream/ ==="
  bash "$REPO_ROOT/apply-patches.sh" "$WORKSPACE" \
    || die "patch series did not apply; refusing to build an unpatched tree"
fi

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
die() { echo "error: $*" >&2; exit 1; }

[ -d "$PREFIX" ] || die "not running inside Termux (\$PREFIX=$PREFIX)"
command -v cargo >/dev/null 2>&1 || die "cargo not found; pkg install rust"
command -v dpkg-deb >/dev/null 2>&1 || die "dpkg-deb not found; pkg install dpkg"

ARCH="$(dpkg --print-architecture)"
VERSION="$(sed -n 's/^version = "\(.*\)"/\1/p' "$WORKSPACE/Cargo.toml" | head -n1)"
[ -n "$VERSION" ] || die "could not read workspace version from upstream/Cargo.toml"
DEB_VERSION="${VERSION}-1"

# --- build --------------------------------------------------------------------
if [ "$SKIP_BUILD" -eq 1 ]; then
  [ -f "$WORKSPACE/target/release/geph5" ] && [ -f "$WORKSPACE/target/release/geph5-client" ] \
    || die "--skip-build: upstream/target/release/{geph5,geph5-client} missing; build first"
  echo "skip-build: reusing upstream/target/release binaries"
else
  # the cd is load-bearing: cargo finds .cargo/config.toml by walking up from cwd
  (cd "$WORKSPACE" && cargo build --release -p geph5-app -p geph5-client)
fi

# --- pack --------------------------------------------------------------------
# The layout itself lives in pack-deb.sh (shared with android/build-module.sh,
# which packages the deb for every arch straight from the desktop cross build).
DEB="android/dist/geph5_${DEB_VERSION}_${ARCH}.deb"
bash "$SCRIPT_DIR/pack-deb.sh" \
    --bin-dir "$WORKSPACE/target/release" \
    --arch "$ARCH" --version "$VERSION" --out "$DEB"
rm -rf android/dist/deb-stage        # staging dir of pre-refactor builds

echo
echo "Install:  pkg install $DEB"
echo "Remove:   apt remove geph5        (purge data: apt purge geph5)"
