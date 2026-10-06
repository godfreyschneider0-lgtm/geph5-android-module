#!/usr/bin/env bash
#
# pack-deb.sh - host-agnostic packer for the geph5 Termux .deb.
#
# Single source of truth for the deb layout, shared by the desktop cross path
# (android/build-module.sh) and the on-device path (android/termux/build-deb.sh):
# both just supply binaries, architecture and version. The templates installed
# as package data (gephsvc, sv service, maintainer scripts) live next to this
# script; the deb layout they produce mirrors install.sh.
#
# Usage:
#   bash android/termux/pack-deb.sh --bin-dir DIR --arch ARCH --version VER --out FILE
#
#     --bin-dir   directory holding the geph5 and geph5-client binaries
#     --arch      dpkg architecture (aarch64, x86_64, ...)
#     --version   upstream workspace version (e.g. 0.4.2); the deb becomes VER-1
#     --out       output .deb path; staging lands in <out dir>/deb-stage-<arch>
#
# Packing uses `dpkg-deb --build --root-owner-group` when available and falls
# back to `ar + tar` on hosts without dpkg. The fallback emits the same shape:
# root:root ownership, gz control, xz data.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "error: $*" >&2; exit 1; }

BIN_DIR="" ARCH="" VERSION="" OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --bin-dir)  [ $# -ge 2 ] || die "--bin-dir needs a value";  BIN_DIR=$2;  shift ;;
    --arch)     [ $# -ge 2 ] || die "--arch needs a value";     ARCH=$2;     shift ;;
    --version)  [ $# -ge 2 ] || die "--version needs a value";  VERSION=$2;  shift ;;
    --out)      [ $# -ge 2 ] || die "--out needs a value";      OUT=$2;      shift ;;
    -h|--help)  sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
  shift
done
[ -n "$BIN_DIR" ] && [ -n "$ARCH" ] && [ -n "$VERSION" ] && [ -n "$OUT" ] \
  || die "need --bin-dir, --arch, --version and --out (see --help)"
[ -x "$BIN_DIR/geph5" ] && [ -x "$BIN_DIR/geph5-client" ] \
  || die "$BIN_DIR does not contain executable geph5 and geph5-client"

DEB_VERSION="${VERSION}-1"
mkdir -p "$(dirname "$OUT")"
STAGE="$(cd "$(dirname "$OUT")" && pwd)/deb-stage-${ARCH}"

# --- stage --------------------------------------------------------------------
# Deb data entries are relative to / (Termux prefix has no leading slash).
PKG="$STAGE/data/data/com.termux/files/usr"
rm -rf "$STAGE"
mkdir -p "$PKG/bin" "$PKG/sv/geph5/log" "$PKG/share/doc/geph5" "$STAGE/DEBIAN"
# Termux's default umask (077) makes these 0700 and dpkg-deb requires >=0755;
# harmless elsewhere. Ship every directory with sane 0755 perms.
find "$STAGE" -type d -exec chmod 0755 {} +

install -m 0755 "$BIN_DIR/geph5"        "$PKG/bin/geph5"
install -m 0755 "$BIN_DIR/geph5-client" "$PKG/bin/geph5-client"
install -m 0755 "$SCRIPT_DIR/gephsvc"   "$PKG/bin/gephsvc"

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
rm -f "$OUT"
if command -v dpkg-deb >/dev/null 2>&1; then
  dpkg-deb --build --root-owner-group "$STAGE" "$OUT"
else
  echo "(dpkg-deb not found; using the ar+tar fallback)" >&2
  T="$(mktemp -d)"
  trap 'rm -rf "$T"' EXIT
  printf '2.0\n' >"$T/debian-binary"
  tar -czf "$T/control.tar.gz" --owner=0 --group=0 --numeric-owner \
      -C "$STAGE/DEBIAN" ./control ./postinst ./prerm ./postrm
  tar -cJf "$T/data.tar.xz" --owner=0 --group=0 --numeric-owner \
      -C "$STAGE" ./data
  ar rc "$OUT" "$T/debian-binary" "$T/control.tar.gz" "$T/data.tar.xz"
fi

echo "packed: $OUT ($(wc -c <"$OUT") bytes)"
