#!/system/bin/sh
# termux-gephctl.sh - control the geph5 KernelSU module from Termux.
# Install as `gephctl`:  bash termux-gephctl.sh --install
# Also runnable directly as root from adb:  /data/local/tmp/gephctl status
# SELinux blocks Termux (untrusted_app) from touching /data/adb, so all
# operations run as root through `su -c`.
DATA=/data/adb/geph5
SOCK="$DATA/control.sock"
PIDF="$DATA/run/manager.pid"
LOGF="$DATA/logs/manager.log"

_resolve_geph() {
  local p
  for p in /data/adb/modules/geph5/geph5 /data/adb/modules_update/geph5/geph5; do
    if [ -x "$p" ] 2>/dev/null; then echo "$p"; return 0; fi
  done
  echo "/data/adb/modules/geph5/geph5"
}
GEPH="$(_resolve_geph)"

SU_PREFIX="su -c"
_ROOT_OK=

# Verify root is available (lazy: only for commands that need it) and probe
# su syntax variants.
require_root() {
  [ -n "$_ROOT_OK" ] && return 0
  if su -c true 2>/dev/null; then
    SU_PREFIX="su -c"; _ROOT_OK=1; return 0
  fi
  if su 0 -c true 2>/dev/null; then
    SU_PREFIX="su 0 -c"; _ROOT_OK=1; return 0
  fi
  echo "error: root required (su unavailable); root the device and grant Termux root access"
  exit 1
}

# Run a command as root; managed paths are fixed (no spaces), user args are
# forwarded verbatim - never eval'd.
as_root() { $SU_PREFIX "$*"; }

# --- service management ------------------------------------------------------
# Whether the manager is actually alive. Use both process and pidfile so a
# leftover control.sock is not mistaken for "running" (geph5 manager does not
# always unlink the socket on exit).
_manager_alive() {
  local pid
  if [ -f "$PIDF" ] 2>/dev/null; then
    pid="$(as_root cat "$PIDF" 2>/dev/null)"
    [ -n "$pid" ] && as_root kill -0 "$pid" 2>/dev/null && return 0
  fi
  as_root pgrep -x geph5 >/dev/null 2>&1 && return 0
  return 1
}

cmd_start() {
  require_root
  as_root mkdir -p "$DATA/logs" "$DATA/run"
  if _manager_alive; then
    echo "geph5 manager already running [already running]"
    return 0
  fi
  # Process is dead but a stale socket/pidfile may remain; clear them so a new
  # instance is not disturbed.
  as_root rm -f "$SOCK" "$PIDF"
  as_root "pkill -TERM -f 'geph5 manager'" 2>/dev/null || true
  sleep 1
  echo "starting geph5 manager... [starting]"
  # Identical startup command to the module service.sh (single su -c, no heredoc).
  as_root 'sh -c "nohup /data/adb/modules/geph5/geph5 manager >>/data/adb/geph5/logs/manager.log 2>&1 & echo \$! >/data/adb/geph5/run/manager.pid"'
  i=0
  while [ "$i" -lt 15 ]; do
    as_root test -S "$SOCK" 2>/dev/null && break
    sleep 1
    i=$((i + 1))
  done
  if _manager_alive && as_root test -S "$SOCK" 2>/dev/null; then
    echo "geph5 manager up [manager up, socket ready]"
  else
    echo "warning: control.sock not ready after 15s [manager may have failed]; see gephctl manager-logs"
    return 1
  fi
}

cmd_stop() {
  require_root
  if as_root test -f "$PIDF" 2>/dev/null; then
    old_pid="$(as_root cat "$PIDF" 2>/dev/null)"
    if [ -n "$old_pid" ]; then
      as_root kill -TERM "$old_pid" 2>/dev/null || true
    fi
    as_root rm -f "$PIDF"
  fi
  as_root "pkill -TERM -f 'geph5 manager'" 2>/dev/null || true
  i=0
  while [ "$i" -lt 5 ]; do
    if ! _manager_alive; then
      as_root rm -f "$SOCK"
      echo "geph5 manager stopped [stopped]"
      return 0
    fi
    sleep 1
    i=$((i + 1))
  done
  echo "warning: manager may still be running [manager may still be running]"
  return 1
}

cmd_status() {
  require_root
  if _manager_alive; then
    echo "manager: running (control.sock ready) [running]"
  else
    echo "manager: not running [not running]; run gephctl start to start the manager"
  fi
  echo "---"
  as_root "$GEPH" status 2>&1 || true
}

cmd_install() {
  local dest="${PREFIX:-/data/data/com.termux/files/usr}/bin/gephctl"
  if mkdir -p "$(dirname "$dest")" 2>/dev/null && cp "$0" "$dest" 2>/dev/null && chmod +x "$dest" 2>/dev/null; then
    echo "gephctl installed to $dest [installed]; now run: gephctl status"
  else
    echo "error: cannot write $dest; run inside Termux (writing \$PREFIX/bin needs Termux permissions)"
    exit 1
  fi
}

# Generic passthrough: every subcommand outside __reserved__ is forwarded to
# geph5 as root, e.g.
#   gephctl connect
#   gephctl exit-constraint set --country us
#   gephctl vpn on
#   gephctl logs -n 50
help() {
  echo "gephctl - geph5 control (thin shell; forwards geph5 subcommands)"
  echo "service [service]: start / stop / restart / status / install / help"
  echo "anything else: any geph5 subcommand works directly, e.g. gephctl connect, gephctl status,"
  echo "      gephctl exit-constraint set --country us, gephctl vpn on, gephctl logs"
  echo "note: register-manager only works on desktop platforms (systemd/launchd/Scheduled Task),"
  echo "      it errors out on Android; this module autostarts via KernelSU service.sh"
  echo "full subcommands: su -c \"$GEPH --help\""
}

# --- dispatch -----------------------------------------------------------------
cmd="${1:-help}"
case "$cmd" in
  install|--install) cmd_install ;;
  start)             cmd_start ;;
  stop)              cmd_stop ;;
  restart)           cmd_stop; cmd_start ;;
  status)            cmd_status ;;
  help|-h|--help)    help ;;
  *)
    # Generic passthrough: run geph5 <cmd> <args...> as root.
    require_root
    shift
    as_root "$GEPH" "$cmd" "$@"
    ;;
esac
