#!/data/data/com.termux/files/usr/bin/bash
#
# install.sh - build geph5 natively in Termux and install it as a
# termux-services (runit/sv) service, no root required.
#
# What it does:
#   1. Preflight: verify Termux + termux-services (+ install hint).
#   2. Ensure a Termux:Boot script starts runsvdir at boot.
#   3. cargo build --release -p geph5-app -p geph5-client (host arch).
#   4. Install $PREFIX/bin/{geph5,geph5-client} (atomic rename).
#   5. Seed ~/.geph5/settings.json with Termux-default proxy ports
#      (SOCKS5 9929 / HTTP 9930) so this install never clashes with a
#      concurrently-running root-module install (9909/9910).
#   6. Install the sv service ($PREFIX/sv/geph5) and enable it.
#   7. Start the manager and wait for its control socket.
#
# Usage:
#   ./android/termux/install.sh [options]
#
# Options:
#   --skip-build           Reuse target/release binaries, do not build.
#   --migrate-from-module  Copy settings + cache from the root module's
#                          /data/adb/geph5 into ~/.geph5 (needs root).
#   --socks5-port <n>      Local SOCKS5 port (default 9929).
#   --http-port <n>        Local HTTP proxy port (default 9930).
#   --pac-port <n>         PAC port via GEPH5_PAC_PORT (default 12233).
#   -h, --help             Show this help.
#
# Requirements: Termux, packages: rust (cargo), termux-services, bash, and the
# Termux:Boot app for autostart.
#
# The Rust source is the upstream/ submodule; this script applies patches/ to
# it before building (same as android/build-module.sh), so a plain checkout
# of this repo builds without any manual preparation step.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# --- defaults (deliberately distinct from the root module's 9909/9910/12223) -
SOCKS5_PORT=9929
HTTP_PORT=9930
PAC_PORT=12233
SKIP_BUILD=0
MIGRATE=0

die() { echo "error: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --skip-build) SKIP_BUILD=1 ;;
    --migrate-from-module) MIGRATE=1 ;;
    --socks5-port) [ $# -ge 2 ] || die "--socks5-port needs a value"; SOCKS5_PORT="$2"; shift ;;
    --http-port)   [ $# -ge 2 ] || die "--http-port needs a value";   HTTP_PORT="$2";   shift ;;
    --pac-port)    [ $# -ge 2 ] || die "--pac-port needs a value";    PAC_PORT="$2";    shift ;;
    -h|--help) sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
  shift
done

# --- preflight ---------------------------------------------------------------
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
[ -d "$PREFIX" ] || die "not running inside Termux (\$PREFIX=$PREFIX)"
HOME_DIR="${HOME:-/data/data/com.termux/files/home}"
STATE_DIR="$HOME_DIR/.geph5"
SVDIR="${SVDIR:-$PREFIX/var/service}"
SVD="$PREFIX/sv/geph5"

command -v cargo >/dev/null 2>&1 \
  || die "cargo not found; install it with: pkg install rust"

if [ ! -x "$PREFIX/bin/sv" ] || [ ! -x "$PREFIX/bin/runsvdir" ]; then
  echo "termux-services missing, installing..."
  pkg install -y termux-services || die "could not install termux-services; run: pkg install termux-services"
fi

# --- Termux:Boot autostart ----------------------------------------------------
# runsvdir must be running for any sv service to be supervised. If no boot
# script already starts it, add one.
boot_dir="$HOME_DIR/.termux/boot"
boot_starter=0
if [ -d "$boot_dir" ]; then
  grep -rls "service-daemon start" "$boot_dir" >/dev/null 2>&1 && boot_starter=1
fi
if [ "$boot_starter" -eq 0 ]; then
  mkdir -p "$boot_dir"
  cat >"$boot_dir/geph5-services.sh" <<'EOF'
#!/data/data/com.termux/files/usr/bin/sh
# Starts the runit service supervisor (termux-services) at boot, which in
# turn starts every enabled service (geph5 included). Requires the
# Termux:Boot app to open once after install.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH=$PREFIX/bin:$PATH
export SVDIR=$PREFIX/var/service
export LOGDIR=$PREFIX/var/log

termux-wake-lock 2>/dev/null
$PREFIX/bin/service-daemon start >/dev/null 2>&1
EOF
  chmod +x "$boot_dir/geph5-services.sh"
  echo "boot: created $boot_dir/geph5-services.sh (needs the Termux:Boot app, opened once)"
else
  echo "boot: an existing Termux:Boot script already starts service-daemon"
fi

# --- build --------------------------------------------------------------------
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

cd "$REPO_ROOT"
if [ "$SKIP_BUILD" -eq 1 ]; then
  [ -f "$WORKSPACE/target/release/geph5" ] && [ -f "$WORKSPACE/target/release/geph5-client" ] \
    || die "--skip-build: upstream/target/release/{geph5,geph5-client} missing; build first"
  echo "skip-build: reusing upstream/target/release binaries"
else
  # the cd is load-bearing: cargo finds .cargo/config.toml by walking up from cwd
  (cd "$WORKSPACE" && cargo build --release -p geph5-app -p geph5-client)
fi

# --- install binaries (atomic rename: never truncate a running binary) --------
install_bin() {
  src="$1" dst="$PREFIX/bin/$2"
  [ -f "$src" ] || die "missing $src"
  cp -f "$src" "$dst.new"
  chmod 0755 "$dst.new"
  mv -f "$dst.new" "$dst"
  echo "installed: $dst"
}
install_bin "$WORKSPACE/target/release/geph5" geph5
install_bin "$WORKSPACE/target/release/geph5-client" geph5-client

# --- seed settings ------------------------------------------------------------
# Partial JSON is fine: every Settings field has a serde default. Ports
# deliberately differ from the root module so both installs can coexist.
if [ ! -f "$STATE_DIR/settings.json" ]; then
  mkdir -p "$STATE_DIR"
  cat >"$STATE_DIR/settings.json" <<EOF
{
  "connected": false,
  "proxy": {
    "autoconf": false,
    "listen_all": false,
    "socks5_port": $SOCKS5_PORT,
    "http_port": $HTTP_PORT
  },
  "vpn": false
}
EOF
  echo "seeded: $STATE_DIR/settings.json (socks5=$SOCKS5_PORT http=$HTTP_PORT)"
else
  echo "keeping existing $STATE_DIR/settings.json"
fi

# --- optional migration from the root module ----------------------------------
if [ "$MIGRATE" -eq 1 ]; then
  if su -c true >/dev/null 2>&1; then
    uid="$(id -u)"; gid="$(id -g)"
    echo "migrating /data/adb/geph5 -> $STATE_DIR (settings + cache)..."
    su -c "cd /data/adb/geph5 && cp -a settings.json '$STATE_DIR/' 2>/dev/null; cp -a cache '$STATE_DIR/' 2>/dev/null; chown -R $uid:$gid '$STATE_DIR'; true"
    # Re-point the migrated proxy ports at the Termux defaults.
    if command -v python >/dev/null 2>&1; then
      python - "$STATE_DIR/settings.json" "$SOCKS5_PORT" "$HTTP_PORT" <<'EOF'
import json, sys
path, socks, http = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
try:
    with open(path) as f:
        s = json.load(f)
except Exception:
    sys.exit(0)
if isinstance(s.get("proxy"), dict):
    s["proxy"]["socks5_port"] = socks
    s["proxy"]["http_port"] = http
    with open(path, "w") as f:
        json.dump(s, f, indent=2)
EOF
    fi
    echo "migration done. Remember to disable/uninstall the root module to avoid"
    echo "two managers fighting over the same exit sessions."
  else
    echo "warning: --migrate-from-module needs root (su unavailable); skipped" >&2
  fi
fi

# --- sv service ---------------------------------------------------------------
mkdir -p "$SVD/log"
sed -e "s|@@PAC_PORT@@|$PAC_PORT|" "$SCRIPT_DIR/sv-run.sh" >"$SVD/run"
cp "$SCRIPT_DIR/sv-log-run.sh" "$SVD/log/run"
chmod 0755 "$SVD/run" "$SVD/log/run"

mkdir -p "$SVDIR"
ln -sfn "$SVD" "$SVDIR/geph5"

# --- gephsvc ------------------------------------------------------------------
# Distinct name from the root module's `gephctl` (su-based): the two control
# different manager instances and must be able to coexist in $PREFIX/bin.
cp "$SCRIPT_DIR/gephsvc" "$PREFIX/bin/gephsvc"
chmod 0755 "$PREFIX/bin/gephsvc"
echo "installed: $PREFIX/bin/gephsvc"

# Clean up a stale Termux-mode gephctl from earlier installs (ours carried this
# marker; the root module's su-based gephctl must be left alone), then restore
# the root module's gephctl if it exists.
if [ -f "$PREFIX/bin/gephctl" ] && grep -q "Termux service install" "$PREFIX/bin/gephctl" 2>/dev/null; then
  rm -f "$PREFIX/bin/gephctl"
  echo "removed stale Termux-mode gephctl (superseded by gephsvc)"
fi
if [ ! -e "$PREFIX/bin/gephctl" ] && su -c 'test -f /data/adb/modules/geph5/gephctl' 2>/dev/null; then
  if su -c 'cat /data/adb/modules/geph5/gephctl' >"$PREFIX/bin/gephctl.new" 2>/dev/null \
    && mv -f "$PREFIX/bin/gephctl.new" "$PREFIX/bin/gephctl" 2>/dev/null; then
    chmod 0755 "$PREFIX/bin/gephctl"
    echo "restored: $PREFIX/bin/gephctl (root module control)"
  fi
fi

# --- start --------------------------------------------------------------------
if ! pgrep -x runsvdir >/dev/null 2>&1; then
  echo "starting service-daemon (runsvdir)..."
  SVDIR="$SVDIR" LOGDIR="$PREFIX/var/log" "$PREFIX/bin/service-daemon" start >/dev/null 2>&1 || true
  sleep 1
fi
sv up geph5 >/dev/null 2>&1 || true

echo "waiting for the manager control socket..."
i=0
while [ "$i" -lt 15 ]; do
  [ -S "$STATE_DIR/control.sock" ] && break
  sleep 1
  i=$((i + 1))
done

echo
if [ -S "$STATE_DIR/control.sock" ]; then
  echo "geph5 manager is up:"
else
  echo "WARNING: control socket not ready after 15s; recent logs:"
  tail -n 10 "$PREFIX/var/log/sv/geph5/current" 2>/dev/null || true
fi
echo "  service:  sv status geph5     (also: gephsvc start/stop/restart)"
echo "  state:    gephsvc status"
echo "  connect:  gephsvc connect     (login first: gephsvc login)"
echo "  socks5:   127.0.0.1:$SOCKS5_PORT   http: 127.0.0.1:$HTTP_PORT   pac: 127.0.0.1:$PAC_PORT"
echo "  data:     $STATE_DIR"
