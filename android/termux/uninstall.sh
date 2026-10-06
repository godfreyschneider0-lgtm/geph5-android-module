#!/data/data/com.termux/files/usr/bin/bash
#
# uninstall.sh - remove the geph5 Termux service, binaries and gephsvc.
# Keeps ~/.geph5 (settings, credentials, cache) unless --purge is given.
#
# Usage: ./android/termux/uninstall.sh [--purge]
set -euo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
SVDIR="${SVDIR:-$PREFIX/var/service}"
STATE_DIR="${HOME:-/data/data/com.termux/files/home}/.geph5"
PURGE=0
[ "${1:-}" = "--purge" ] && PURGE=1

if [ -x "$PREFIX/bin/sv" ]; then
  sv down geph5 >/dev/null 2>&1 || true
fi
rm -f "$SVDIR/geph5"
rm -rf "$PREFIX/sv/geph5"
rm -f "$PREFIX/bin/geph5" "$PREFIX/bin/geph5-client" "$PREFIX/bin/gephsvc"
# Remove a stale Termux-mode gephctl from earlier installs only; the root
# module's su-based gephctl (no such marker) is not ours to delete.
if [ -f "$PREFIX/bin/gephctl" ] && grep -q "Termux service install" "$PREFIX/bin/gephctl" 2>/dev/null; then
  rm -f "$PREFIX/bin/gephctl"
fi

if [ "$PURGE" -eq 1 ]; then
  rm -rf "$STATE_DIR"
  echo "removed: $STATE_DIR (settings + cache)"
else
  echo "kept: $STATE_DIR (use --purge to delete settings + cache)"
fi
echo "geph5 Termux service uninstalled."
