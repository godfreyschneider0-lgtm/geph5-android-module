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

# 校验 root 可用 (惰性: 仅需 root 的命令调用), 并探测 su 语法变体。
require_root() {
  [ -n "$_ROOT_OK" ] && return 0
  if su -c true 2>/dev/null; then
    SU_PREFIX="su -c"; _ROOT_OK=1; return 0
  fi
  if su 0 -c true 2>/dev/null; then
    SU_PREFIX="su 0 -c"; _ROOT_OK=1; return 0
  fi
  echo "错误 [error]: 需要 root 权限 (su 不可用); 请确认设备已 root 且已授予 Termux root 权限"
  exit 1
}

# 以 root 执行命令; 受管路径均为固定路径 (无空格), 用户参数原样透传, 绝不 eval。
as_root() { $SU_PREFIX "$*"; }

# --- 服务管理 ---------------------------------------------------------------
# 管理器是否实际存活。以进程 + PID 文件双重判断, 避免残留的 control.sock
# 文件被误判为"运行中" (geph5 manager 退出时不一定 unlink socket)。
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
    echo "geph5 管理器已在运行 [already running]"
    return 0
  fi
  # 进程已死但残留 socket/pid 文件, 清掉避免干扰新实例。
  as_root rm -f "$SOCK" "$PIDF"
  as_root "pkill -TERM -f 'geph5 manager'" 2>/dev/null || true
  sleep 1
  echo "正在启动 geph5 manager... [starting]"
  # 与模块 service.sh 完全一致的启动命令 (单行 su -c, 无 heredoc)。
  as_root 'sh -c "nohup /data/adb/modules/geph5/geph5 manager >>/data/adb/geph5/logs/manager.log 2>&1 & echo \$! >/data/adb/geph5/run/manager.pid"'
  i=0
  while [ "$i" -lt 15 ]; do
    as_root test -S "$SOCK" 2>/dev/null && break
    sleep 1
    i=$((i + 1))
  done
  if _manager_alive && as_root test -S "$SOCK" 2>/dev/null; then
    echo "geph5 管理器已启动 [manager up, socket ready]"
  else
    echo "警告: control.sock 15 秒内未就绪 [manager may have failed]; 查看 gephctl manager-logs"
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
      echo "geph5 管理器已停止 [stopped]"
      return 0
    fi
    sleep 1
    i=$((i + 1))
  done
  echo "警告: 管理器可能仍在运行 [manager may still be running]"
  return 1
}

cmd_status() {
  require_root
  if _manager_alive; then
    echo "manager: 运行中 (control.sock 就绪) [running]"
  else
    echo "manager: 未运行 [not running]; 运行 gephctl start 启动管理器"
  fi
  echo "---"
  as_root "$GEPH" status 2>&1 || true
}

cmd_install() {
  local dest="${PREFIX:-/data/data/com.termux/files/usr}/bin/gephctl"
  if mkdir -p "$(dirname "$dest")" 2>/dev/null && cp "$0" "$dest" 2>/dev/null && chmod +x "$dest" 2>/dev/null; then
    echo "已安装 gephctl 到 $dest [installed]; 现在可以直接运行: gephctl status"
  else
    echo "错误 [error]: 无法写入 $dest; 请确认在 Termux 中运行 (写入 \$PREFIX/bin 需要 Termux 权限)"
    exit 1
  fi
}

# 通用透传: 除 __reserved__ 之外的所有子命令直接以 root 转发给 geph5, 例如
#   gephctl connect
#   gephctl exit-constraint set --country us
#   gephctl vpn on
#   gephctl logs -n 50
help() {
  echo "gephctl - geph5 控制 (薄壳, 直接透传 geph5 子命令)"
  echo "服务 [service]: start / stop / restart / status / install / help"
  echo "其他: 任意 geph5 子命令直接可用, 例如 gephctl connect、gephctl status、"
  echo "      gephctl exit-constraint set --country us、gephctl vpn on、gephctl logs"
  echo "注意: register-manager 仅桌面平台有效 (systemd/launchd/计划任务),"
  echo "      Android 上会报错; 本模块开机自启由 KernelSU 的 service.sh 负责"
  echo "完整子命令见: su -c \"$GEPH --help\""
}

# --- 分发 -------------------------------------------------------------------
cmd="${1:-help}"
case "$cmd" in
  install|--install) cmd_install ;;
  start)             cmd_start ;;
  stop)              cmd_stop ;;
  restart)           cmd_stop; cmd_start ;;
  status)            cmd_status ;;
  help|-h|--help)    help ;;
  *)
    # 通用透传: 以 root 运行 geph5 <cmd> <args...>。
    require_root
    shift
    as_root "$GEPH" "$cmd" "$@"
    ;;
esac
