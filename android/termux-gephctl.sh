#!/usr/bin/env bash
# termux-gephctl.sh - control the geph5 KernelSU module from Termux.
# Install as `gephctl`:  bash termux-gephctl.sh --install
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
cmd_start() {
  require_root
  as_root mkdir -p "$DATA/logs" "$DATA/run"
  if as_root test -S "$SOCK" 2>/dev/null; then
    echo "geph5 管理器已在运行 [already running]"
    return 0
  fi
  if as_root test -f "$PIDF" 2>/dev/null; then
    old_pid="$(as_root cat "$PIDF" 2>/dev/null)"
    if [ -n "$old_pid" ]; then
      as_root kill -TERM "$old_pid" 2>/dev/null || true
    fi
    as_root rm -f "$PIDF"
  fi
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
  if as_root test -S "$SOCK" 2>/dev/null; then
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
    if ! as_root test -S "$SOCK" 2>/dev/null; then
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
  if as_root test -S "$SOCK" 2>/dev/null; then
    echo "manager: 运行中 (control.sock 就绪) [running]"
  elif as_root test -f "$PIDF" 2>/dev/null; then
    echo "manager: pid 文件存在但 socket 未就绪 [starting or crashed]; 查看 gephctl manager-logs"
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

cmd_set_exit() {  # set-exit <cc> [city]
  local cc city
  require_root
  [ $# -ge 2 ] || { echo "用法 [usage]: gephctl set-exit <国家代码> [城市]"; exit 1; }
  cc="$2"
  case "$cc" in
    [A-Za-z][A-Za-z]) ;;
    *) echo "错误: 国家代码应为两位字母, 如 CN/US/JP"; exit 1 ;;
  esac
  city="${3:-}"
  as_root "$GEPH" exit-constraint set --country "$cc" ${city:+--city "$city"}
}

cmd_onoff() {  # proxy|vpn on|off
  local mode
  require_root
  mode="$1"
  [ $# -ge 3 ] || { echo "用法 [usage]: gephctl $mode on|off"; exit 1; }
  case "$3" in
    on|off) as_root "$GEPH" "$mode" "$3" ;;
    *) echo "错误: 参数应为 on 或 off"; exit 1 ;;
  esac
}

cmd_manager_logs() {  # manager-logs [n]
  local n
  require_root
  n="${2:-50}"
  case "$n" in
    *[!0-9]*|"") n=50 ;;
  esac
  as_root tail -n "$n" "$LOGF"
}

help() {
  cat <<'EOF'
gephctl - 控制 geph5 KernelSU 模块 [control the geph5 module]
服务 [service]:
  start            启动管理器 (开机自启; 崩溃/重启后手动启动)
  stop             停止管理器
  restart          重启管理器
  status           管理器状态 + geph5 连接状态
连接 [connection]:
  connect          连接 (首次需先 login)
  disconnect       断开
  reconnect        重连
  login [secret]   登录 (无参数则提示)
  logout           退出登录
  register         注册新账号
  account          账号信息
出口 [exit nodes]:
  exits / exit-list    列出出口节点
  set-exit <cc> [city] 设置出口, 如 set-exit JP
  proxy on|off         代理模式开/关
  vpn on|off           VPN 模式开/关
日志 [logs]:
  logs [-n N]       geph5 CLI 日志 (默认 20 行)
  manager-logs [n]  管理器日志 (默认 50 行)
其他 [other]:
  install           安装 gephctl 到 Termux (usr/bin/gephctl)
  help              显示本帮助
EOF
}

# --- 分发 -------------------------------------------------------------------
cmd="${1:-help}"
case "$cmd" in
  install|--install) cmd_install ;;
  help|-h|--help)    help ;;
  start)             cmd_start ;;
  stop)              cmd_stop ;;
  restart)           cmd_stop; cmd_start ;;
  status)            cmd_status ;;
  connect|disconnect|reconnect|login|logout|register|account|exits|logs)
    require_root
    shift
    as_root "$GEPH" "$cmd" "$@"
    ;;
  exit-list)     require_root; as_root "$GEPH" exits ;;
  set-exit)      cmd_set_exit "$@" ;;
  proxy|vpn)     cmd_onoff "$cmd" "$@" ;;
  manager-logs)  cmd_manager_logs "$@" ;;
  *)
    echo "错误 [error]: 未知命令 '$cmd'"
    help
    exit 1
    ;;
esac
