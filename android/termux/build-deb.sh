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
# The Rust source is the upstream/ submodule; this script applies patches/ to
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

# --- upstream workspace ----------------------------------------------------
# Same contract as android/build-module.sh: never build an unpatched tree.
WORKSPACE="$REPO_ROOT/upstream"
if [ ! -f "$WORKSPACE/Cargo.toml" ]; then
  die "upstream/ is not initialised. Run:
       git submodule update --init --recursive upstream"
fi
if [ "$SKIP_BUILD" -eq 1 ]; then
  "$REPO_ROOT/apply-patches.sh" --check "$WORKSPACE" \
    || die "patch series does not apply to upstream/ (--skip-build was given)"
else
  echo "=== applying patch series to upstream/ ==="
  "$REPO_ROOT/apply-patches.sh" "$WORKSPACE" \
    || die "patch series did not apply; refusing to build an unpatched tree"
fi

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
die() { echo "error: $*" >&2; exit 1; }

SKIP_BUILD=0
[ "${1:-}" = "--skip-build" ] && SKIP_BUILD=1

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

# --- stage --------------------------------------------------------------------
# Deb data entries are relative to / (Termux prefix has no leading slash).
STAGE="android/dist/deb-stage"
PKG="$STAGE/data/data/com.termux/files/usr"
rm -rf "$STAGE"
mkdir -p "$PKG/bin" "$PKG/sv/geph5/log" "$PKG/share/doc/geph5" "$STAGE/DEBIAN"
# Termux's default umask (077) makes these 0700; dpkg-deb requires >=0755.
chmod 0755 "$STAGE" "$STAGE/DEBIAN"
# ...and ship every directory with sane 0755 perms, not the local umask's.
find "$STAGE" -type d -exec chmod 0755 {} +

install -m 0755 "$WORKSPACE/target/release/geph5"        "$PKG/bin/geph5"
install -m 0755 "$WORKSPACE/target/release/geph5-client" "$PKG/bin/geph5-client"
install -m 0755 "$SCRIPT_DIR/gephsvc"       "$PKG/bin/gephsvc"

# Same templates as install.sh (single source of truth for the service).
sed 's|@@PAC_PORT@@|12233|' "$SCRIPT_DIR/sv-run.sh" >"$PKG/sv/geph5/run"
install -m 0755 "$SCRIPT_DIR/sv-log-run.sh" "$PKG/sv/geph5/log/run"
chmod 0755 "$PKG/sv/geph5/run"

install -m 0644 "$SCRIPT_DIR/README.md" "$PKG/share/doc/geph5/README.md"

for f in postinst prerm postrm; do
  install -m 0755 "$SCRIPT_DIR/deb/$f" "$STAGE/DEBIAN/$f"
done

INSTALLED_SIZE="$(du -sk "$STAGE/data" | cut -f1)"

cat >"$STAGE/DEBIAN/control" <<EOF
Package: geph5
Version: $DEB_VERSION
Architecture: $ARCH
Maintainer: geph <dev@geph.org>
Installed-Size: $INSTALLED_SIZE
Depends: termux-services
Section: net
Priority: optional
Homepage: https://geph.io
Description: Geph5 anti-censorship network - Termux service install
 Geph5 runs as the Termux user (no root) under termux-services (runit)
 supervision, autostarting at boot via Termux:Boot. Provides local SOCKS5
 (127.0.0.1:9929) and HTTP (127.0.0.1:9930) proxies through the Geph
 network. Control with gephsvc; VPN full-tunnel mode is unsupported on
 Android (proxy mode only, like the root module).
EOF

# --- pack ---------------------------------------------------------------------
DEB="android/dist/geph5_${DEB_VERSION}_${ARCH}.deb"
rm -f "$DEB"
dpkg-deb --build --root-owner-group "$STAGE" "$DEB"

echo
echo "=== built: $DEB ($(wc -c <"$DEB") bytes) ==="
dpkg-deb -I "$DEB" | sed -n '1,12p'
echo "--- contents:"
dpkg-deb -c "$DEB" | awk '{print $1, $6}' | sed 's|^|  |'

echo
echo "Install:  pkg install $DEB"
echo "Remove:   apt remove geph5        (purge data: apt purge geph5)"
