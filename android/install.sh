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

die() { echo "错误 [error]: $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
用法 [Usage]: install.sh [zip] [选项]

  不指定 zip 时使用本脚本目录 dist/ 下最新的 geph5-ksu-*-arm64.zip。

选项 [options]:
  --zip <path>      指定模块 zip 路径
  --reboot          安装成功后自动重启设备 (仅 HOST 模式)
  --no-reboot       不重启、不询问
  -h, --help        显示本帮助

运行模式 [modes] (自动检测):
  HOST   宿主电脑 + adb, 设备已授权
  DEVICE 设备端 Termux 中直接运行
EOF
}

ZIP=""
REBOOT=auto
while [ $# -gt 0 ]; do
  case "$1" in
    --zip)
      [ $# -ge 2 ] || die "--zip 需要一个路径参数"
      [ -z "$ZIP" ] || die "zip 路径重复指定"
      ZIP="$2"; shift ;;
    --reboot)    REBOOT=yes ;;
    --no-reboot) REBOOT=no ;;
    -h|--help)   usage; exit 0 ;;
    --*)         die "未知参数: $1 (见 --help)" ;;
    *)           [ -z "$ZIP" ] || die "zip 路径重复指定: $1"
                 ZIP="$1" ;;
  esac
  shift
done

if [ -z "$ZIP" ]; then
  ZIP="$(ls -1t "$SCRIPT_DIR"/dist/geph5-ksu-*-arm64.zip 2>/dev/null | head -n1 || true)"
fi
[ -n "$ZIP" ] || die "未找到模块 zip; 请先运行 android/build-module.sh 或指定 zip 路径"
[ -f "$ZIP" ] || die "zip 不存在: $ZIP"
command -v unzip >/dev/null 2>&1 || die "宿主需要 unzip 命令 [host requires unzip]"
unzip -p "$ZIP" module.prop >/dev/null 2>&1 || die "zip 中缺少 module.prop, 不是有效的 geph5 模块包: $ZIP"
echo "==> 模块包 [module zip]: $ZIP"

# --- 设备端安装链 (POSIX sh, 以 root 运行) ------------------------------------
# 注意: 模板内禁止出现单引号 (HOST 模式需经 adb 单引号透传)。
CHAIN='ZIP=__ZIP__
MODID=geph5
echo "[geph5] installing: $ZIP"
[ -f "$ZIP" ] || { echo "[geph5] error: zip not found on device"; echo "__GEPH5_RESULT__=fail"; exit 1; }
ksud=
command -v ksud >/dev/null 2>&1 && ksud=ksud
[ -n "$ksud" ] || { [ -x /data/adb/ksud ] && ksud=/data/adb/ksud; }
[ -n "$ksud" ] || { [ -x /debug_ramdisk/ksud ] && ksud=/debug_ramdisk/ksud; }
if [ -n "$ksud" ]; then
  echo "[geph5] try ksud (KernelSU)..."
  if "$ksud" module install "$ZIP" >/dev/null 2>&1; then echo "__GEPH5_RESULT__=ok"; exit 0; fi
  echo "[geph5] ksud failed"
fi
magisk=
command -v magisk >/dev/null 2>&1 && magisk=magisk
[ -n "$magisk" ] || { [ -x /sbin/magisk ] && magisk=/sbin/magisk; }
if [ -n "$magisk" ]; then
  echo "[geph5] try magisk --install-module..."
  if "$magisk" --install-module "$ZIP" >/dev/null 2>&1; then echo "__GEPH5_RESULT__=ok"; exit 0; fi
  echo "[geph5] magisk failed"
fi
apd=
command -v apd >/dev/null 2>&1 && apd=apd
[ -n "$apd" ] || { [ -x /data/adb/ap/bin/apd ] && apd=/data/adb/ap/bin/apd; }
[ -n "$apd" ] || { [ -x /data/adb/apd ] && apd=/data/adb/apd; }
if [ -n "$apd" ]; then
  echo "[geph5] try apd (APatch)..."
  if "$apd" module install "$ZIP" >/dev/null 2>&1; then echo "__GEPH5_RESULT__=ok"; exit 0; fi
  echo "[geph5] apd failed"
fi
echo "[geph5] manual fallback: stage into /data/adb/modules_update/$MODID"
rm -rf "/data/adb/modules_update/$MODID"
mkdir -p "/data/adb/modules_update/$MODID" || { echo "__GEPH5_RESULT__=fail"; exit 1; }
cd "/data/adb/modules_update/$MODID" || { echo "__GEPH5_RESULT__=fail"; exit 1; }
if command -v unzip >/dev/null 2>&1; then
  unzip -qo "$ZIP" || { echo "__GEPH5_RESULT__=fail"; exit 1; }
elif [ -x /system/bin/unzip ]; then
  /system/bin/unzip -qo "$ZIP" || { echo "__GEPH5_RESULT__=fail"; exit 1; }
else
  echo "[geph5] error: no unzip on device; use the KernelSU manager instead"
  echo "__GEPH5_RESULT__=fail"; exit 1
fi
[ -f module.prop ] || { echo "[geph5] error: module.prop missing after unzip"; echo "__GEPH5_RESULT__=fail"; exit 1; }
chmod 0755 geph5 geph5-client 2>/dev/null
echo "__GEPH5_RESULT__=staged"; exit 0'

# 生成设备端脚本: 把首行 ZIP=__ZIP__ 替换为实际路径 (printf %q 保证引号安全)。
build_chain() {  # $1 = 设备端 zip 路径
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
    ok)     echo "==> 安装成功 [installed]" ;;
    staged) echo "==> 已暂存到 modules_update, 重启后完成安装 [staged, applies on reboot]" ;;
    fail)   echo "==> 安装失败 [install failed]; 可尝试在 KernelSU 管理器中手动安装此 zip" ;;
    *)      echo "==> 无法识别安装结果, 请检查设备 root/su 状态 [unknown result]" ;;
  esac
}

# --- HOST 模式 ---------------------------------------------------------------
maybe_reboot_host() {
  local ans
  if [ "$REBOOT" = yes ]; then
    adb reboot >/dev/null 2>&1 && echo "已发送重启指令 [rebooting now]"
  elif [ "$REBOOT" = auto ] && [ -t 0 ]; then
    printf "是否立即重启设备? 重启后模块加载生效 [y/N]: "
    read -r ans
    case "$ans" in
      y|Y) adb reboot >/dev/null 2>&1 && echo "已发送重启指令 [rebooting now]" ;;
      *)   echo "请稍后手动重启设备 [reboot manually later]" ;;
    esac
  else
    echo "请稍后手动重启设备 [reboot manually later]"
  fi
}

host_install() {
  local chain qchain out result
  command -v adb >/dev/null 2>&1 || die "未找到 adb 命令 [adb not found]"
  echo "==> 推送 zip 到设备 [adb push]"
  adb push "$ZIP" /data/local/tmp/geph5-ksu.zip || die "adb push 失败, 请检查设备连接"
  chain="$(build_chain /data/local/tmp/geph5-ksu.zip)"
  [[ "$chain" != *"'"* ]] || die "内部错误: 安装链含单引号, 无法经 adb 传输"
  qchain="'$chain'"
  echo "==> 在设备上以 root 执行安装 [running installer on device]"
  out="$(adb shell "su -c $qchain || su 0 -c $qchain" 2>&1 || true)"
  out="${out//$'\r'/}"
  result="$(parse_result "$out")"
  printf '%s\n' "$out"
  report_result "$result"
  if [ "$result" = ok ] || [ "$result" = staged ]; then
    adb shell rm -f /data/local/tmp/geph5-ksu.zip >/dev/null 2>&1 || true
    echo "==> 已清理设备端临时文件 [cleaned up /data/local/tmp/geph5-ksu.zip]"
    maybe_reboot_host
  else
    echo "==> 设备端临时文件已保留: /data/local/tmp/geph5-ksu.zip (可手动排查)"
  fi
}

# --- DEVICE 模式 -------------------------------------------------------------
device_install() {
  local su_bin chain out result
  su_bin="$(command -v su 2>/dev/null || true)"
  [ -n "$su_bin" ] || { [ -x /system/bin/su ] && su_bin=/system/bin/su; }
  [ -n "$su_bin" ] || { [ -x /system/xbin/su ] && su_bin=/system/xbin/su; }
  [ -n "$su_bin" ] || die "未找到 su, 请确认设备已 root (KernelSU/Magisk/APatch)"
  chain="$(build_chain "$ZIP")"
  echo "==> 以 root 执行安装 [running installer via su]"
  out="$("$su_bin" -c "$chain" 2>&1 || "$su_bin" 0 -c "$chain" 2>&1 || true)"
  result="$(parse_result "$out")"
  printf '%s\n' "$out"
  report_result "$result"
  if [ "$result" = ok ] || [ "$result" = staged ]; then
    if [ -f "$SCRIPT_DIR/termux-gephctl.sh" ]; then
      echo "==> 可安装 Termux 控制工具 gephctl [optional]"
      echo "    bash $SCRIPT_DIR/termux-gephctl.sh --install"
    fi
    echo "==> 请重启设备使模块加载生效 [reboot to activate]"
  fi
}

# --- 模式检测 ---------------------------------------------------------------
detect_mode() {
  local st=""
  if command -v timeout >/dev/null 2>&1; then
    st="$(timeout 5 adb get-state 2>/dev/null || true)"
  elif command -v adb >/dev/null 2>&1; then
    st="$(adb get-state 2>/dev/null || true)"
  fi
  if [ "$st" = device ]; then
    echo "==> 安装方式 [mode]: HOST (adb 连接)"
    host_install
    return
  fi
  if [ -d /data/data/com.termux ] || [ "$(uname -o 2>/dev/null)" = Android ]; then
    echo "==> 安装方式 [mode]: DEVICE (Termux 直装)"
    device_install
    return
  fi
  die "无法确定运行模式:
  电脑上: 连接已 root 的设备并运行本脚本 (需 adb, 设备已授权)
  设备上: 在已 root 设备的 Termux 中直接运行本脚本"
}

detect_mode
