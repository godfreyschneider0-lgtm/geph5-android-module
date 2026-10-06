#!/usr/bin/env bash
#
# install.sh - one-click installer for the geph5 KernelSU module zip.
#
# Two modes (auto-detected):
#   HOST    - PC with adb, device authorized (adb get-state -> device)
#   DEVICE  - run directly inside Termux on the rooted device
# The install itself runs as root on the device and tries, in order:
#   ksud (KernelSU) -> magisk --install-module -> apd (APatch)
#   -> manual fallback (stage into /data/adb/modules_update, applies on reboot)
#
# Usage: ./android/install.sh [zip] [--zip <path>] [--reboot|--no-reboot]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "error: $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: install.sh [zip] [options]

  When no zip is given, the newest geph5-ksu-*-arm64.zip under this script's
  dist/ directory is used.

Options:
  --zip <path>      path to the module zip
  --reboot          reboot the device after a successful install (HOST mode only)
  --no-reboot       do not reboot and do not ask
  -h, --help        show this help

Modes (auto-detected):
  HOST   host PC + adb, device authorized
  DEVICE run directly inside Termux on the rooted device
EOF
}

ZIP=""
REBOOT=auto
while [ $# -gt 0 ]; do
  case "$1" in
    --zip)
      [ $# -ge 2 ] || die "--zip needs a path argument"
      [ -z "$ZIP" ] || die "zip path given more than once"
      ZIP="$2"; shift ;;
    --reboot)    REBOOT=yes ;;
    --no-reboot) REBOOT=no ;;
    -h|--help)   usage; exit 0 ;;
    --*)         die "unknown argument: $1 (see --help)" ;;
    *)           [ -z "$ZIP" ] || die "zip path given more than once: $1"
                 ZIP="$1" ;;
  esac
  shift
done

if [ -z "$ZIP" ]; then
  ZIP="$(ls -1t "$SCRIPT_DIR"/dist/geph5-ksu-*-arm64.zip 2>/dev/null | head -n1 || true)"
fi
[ -n "$ZIP" ] || die "no module zip found; run android/build-module.sh first or pass a zip path"
[ -f "$ZIP" ] || die "zip not found: $ZIP"
command -v unzip >/dev/null 2>&1 || die "the host needs the unzip command"
unzip -p "$ZIP" module.prop >/dev/null 2>&1 || die "zip has no module.prop; not a valid geph5 module package: $ZIP"
echo "==> module zip: $ZIP"

# --- device-side install chain (POSIX sh, run as root) -----------------------
# Note: the template must not contain single quotes (HOST mode pipes it through
# adb with single-quote wrapping).
CHAIN='ZIP=__ZIP__
MODID=geph5
echo "[geph5] installing: $ZIP"
[ -f "$ZIP" ] || { echo "[geph5] error: zip not found on device"; echo "__GEPH5_RESULT__=fail"; exit 1; }
# deploy_gephctl: deploy the Termux control script at flash time. Prefer the
# Termux $PREFIX/bin (executable), otherwise fall back to /data/local/tmp/gephctl.
deploy_gephctl() {
  local src dest
  src="/data/adb/modules/$MODID/gephctl"
  [ -f "$src" ] || src="/data/adb/modules_update/$MODID/gephctl"
  [ -f "$src" ] || { echo "[geph5] gephctl not found in module"; return 0; }
  if [ -d /data/data/com.termux/files/usr/bin ]; then
    dest=/data/data/com.termux/files/usr/bin/gephctl
    cp -f "$src" "$dest" 2>/dev/null && chmod 0755 "$dest" 2>/dev/null \
      && echo "[geph5] gephctl -> $dest [Termux]" && return 0
  fi
  dest=/data/local/tmp/gephctl
  cp -f "$src" "$dest" 2>/dev/null && chmod 0755 "$dest" 2>/dev/null \
    && echo "[geph5] gephctl -> $dest [fallback: Termux not installed]" || true
}
ksud=
command -v ksud >/dev/null 2>&1 && ksud=ksud
[ -n "$ksud" ] || { [ -x /data/adb/ksud ] && ksud=/data/adb/ksud; }
[ -n "$ksud" ] || { [ -x /debug_ramdisk/ksud ] && ksud=/debug_ramdisk/ksud; }
if [ -n "$ksud" ]; then
  echo "[geph5] try ksud (KernelSU)..."
  if "$ksud" module install "$ZIP" >/dev/null 2>&1; then deploy_gephctl; echo "__GEPH5_RESULT__=ok"; exit 0; fi
  echo "[geph5] ksud failed"
fi
magisk=
command -v magisk >/dev/null 2>&1 && magisk=magisk
[ -n "$magisk" ] || { [ -x /sbin/magisk ] && magisk=/sbin/magisk; }
if [ -n "$magisk" ]; then
  echo "[geph5] try magisk --install-module..."
  if "$magisk" --install-module "$ZIP" >/dev/null 2>&1; then deploy_gephctl; echo "__GEPH5_RESULT__=ok"; exit 0; fi
  echo "[geph5] magisk failed"
fi
apd=
command -v apd >/dev/null 2>&1 && apd=apd
[ -n "$apd" ] || { [ -x /data/adb/ap/bin/apd ] && apd=/data/adb/ap/bin/apd; }
[ -n "$apd" ] || { [ -x /data/adb/apd ] && apd=/data/adb/apd; }
# stage_apatch: unzip into both modules/<id> and modules_update/<id> so the
# module takes effect right away regardless of whether modules_update->modules
# is promoted on the next reboot.
stage_files() {
  local d
  for d in "/data/adb/modules/$MODID" "/data/adb/modules_update/$MODID"; do
    rm -rf "$d"
    mkdir -p "$d" || { echo "__GEPH5_RESULT__=fail"; exit 1; }
    if command -v unzip >/dev/null 2>&1; then
      ( cd "$d" && unzip -qo "$ZIP" ) || { echo "__GEPH5_RESULT__=fail"; exit 1; }
    elif [ -x /system/bin/unzip ]; then
      ( cd "$d" && /system/bin/unzip -qo "$ZIP" ) || { echo "__GEPH5_RESULT__=fail"; exit 1; }
    elif [ -x /data/adb/ap/bin/busybox ]; then
      ( cd "$d" && /data/adb/ap/bin/busybox unzip -qo "$ZIP" ) || { echo "__GEPH5_RESULT__=fail"; exit 1; }
    else
      echo "[geph5] error: no unzip on device; use the KernelSU manager instead"
      echo "__GEPH5_RESULT__=fail"; exit 1
    fi
    [ -f "$d/module.prop" ] || { echo "[geph5] error: module.prop missing after unzip"; echo "__GEPH5_RESULT__=fail"; exit 1; }
    chmod 0755 "$d/geph5" "$d/geph5-client" "$d/service.sh" "$d/action.sh" "$d/uninstall.sh" "$d/gephctl" 2>/dev/null
   done
}
if [ -n "$apd" ]; then
  echo "[geph5] try apd (APatch)..."
  if "$apd" module install "$ZIP" >/dev/null 2>&1; then
    stage_files
    deploy_gephctl
    echo "__GEPH5_RESULT__=ok"
    exit 0
  fi
  echo "[geph5] apd failed"
fi
echo "[geph5] manual fallback: stage into modules/$MODID"
stage_files
deploy_gephctl
echo "__GEPH5_RESULT__=staged"; exit 0'

# Generate the device script: replace the leading ZIP=__ZIP__ line with the
# real path (printf %q keeps quoting safe).
build_chain() {  # $1 = device-side zip path
  printf 'ZIP=%s\n%s\n' "$(printf '%q' "$1")" "${CHAIN#*$'\n'}"
}

parse_result() {
  case "$1" in
    *"__GEPH5_RESULT__=ok"*)     echo ok ;;
    *"__GEPH5_RESULT__=staged"*) echo staged ;;
    *"__GEPH5_RESULT__=fail"*)   echo fail ;;
    *) echo unknown ;;
  esac
}

report_result() {
  case "$1" in
    ok)     echo "==> installed" ;;
    staged) echo "==> staged into modules_update; completes on reboot" ;;
    fail)   echo "==> install failed; try installing this zip from the KernelSU manager" ;;
    *)      echo "==> unrecognized install result; check the device root/su state" ;;
  esac
}

# --- HOST mode ---------------------------------------------------------------
maybe_reboot_host() {
  local ans
  if [ "$REBOOT" = yes ]; then
    adb reboot >/dev/null 2>&1 && echo "rebooting now"
  elif [ "$REBOOT" = auto ] && [ -t 0 ]; then
    printf "Reboot now so the module loads? [y/N]: "
    read -r ans
    case "$ans" in
      y|Y) adb reboot >/dev/null 2>&1 && echo "rebooting now" ;;
      *)   echo "reboot manually later" ;;
    esac
  else
    echo "reboot manually later"
  fi
}

host_install() {
  local chain qchain out result
  command -v adb >/dev/null 2>&1 || die "adb not found"
  echo "==> pushing zip to device [adb push]"
  adb push "$ZIP" /data/local/tmp/geph5-ksu.zip || die "adb push failed; check the device connection"
  chain="$(build_chain /data/local/tmp/geph5-ksu.zip)"
  [[ "$chain" != *"'"* ]] || die "internal error: install chain contains a single quote; cannot send via adb"
  qchain="'$chain'"
  echo "==> running installer as root on device"
  out="$(adb shell "su -c $qchain || su 0 -c $qchain" 2>&1 || true)"
  out="${out//$'\r'/}"
  result="$(parse_result "$out")"
  printf '%s\n' "$out"
  report_result "$result"
  if [ "$result" = ok ] || [ "$result" = staged ]; then
    adb shell rm -f /data/local/tmp/geph5-ksu.zip >/dev/null 2>&1 || true
    echo "==> cleaned up /data/local/tmp/geph5-ksu.zip"
    maybe_reboot_host
  else
    echo "==> kept device-side temp file: /data/local/tmp/geph5-ksu.zip (for manual debugging)"
  fi
}

# --- DEVICE mode -------------------------------------------------------------
device_install() {
  local su_bin chain out result
  su_bin="$(command -v su 2>/dev/null || true)"
  [ -n "$su_bin" ] || { [ -x /system/bin/su ] && su_bin=/system/bin/su; }
  [ -n "$su_bin" ] || { [ -x /system/xbin/su ] && su_bin=/system/xbin/su; }
  [ -n "$su_bin" ] || die "su not found; make sure the device is rooted (KernelSU/Magisk/APatch)"
  chain="$(build_chain "$ZIP")"
  echo "==> running installer as root via su"
  out="$("$su_bin" -c "$chain" 2>&1 || "$su_bin" 0 -c "$chain" 2>&1 || true)"
  result="$(parse_result "$out")"
  printf '%s\n' "$out"
  report_result "$result"
  if [ "$result" = ok ] || [ "$result" = staged ]; then
    if [ -f "$SCRIPT_DIR/termux-gephctl.sh" ]; then
      echo "==> optional: install the Termux control tool gephctl"
      echo "    bash $SCRIPT_DIR/termux-gephctl.sh --install"
    fi
    echo "==> reboot the device to activate the module"
  fi
}

# --- mode detection -----------------------------------------------------------
detect_mode() {
  local st=""
  if command -v timeout >/dev/null 2>&1; then
    st="$(timeout 5 adb get-state 2>/dev/null || true)"
  elif command -v adb >/dev/null 2>&1; then
    st="$(adb get-state 2>/dev/null || true)"
  fi
  if [ "$st" = device ]; then
    echo "==> mode: HOST (adb connection)"
    host_install
    return
  fi
  if [ -d /data/data/com.termux ] || [ "$(uname -o 2>/dev/null)" = Android ]; then
    echo "==> mode: DEVICE (direct Termux install)"
    device_install
    return
  fi
  die "cannot determine mode:
  on a PC:   connect a rooted device and run this script (needs adb, authorized device)
  on-device: run this script inside Termux on the rooted device"
}

detect_mode
