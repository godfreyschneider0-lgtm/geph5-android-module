#!/data/data/com.termux/files/usr/bin/sh
# svlogd logger for the geph5 service: appends to $LOGDIR/sv/geph5/current
# with automatic size-based rotation (svlogd defaults).

export LOGDIR="${LOGDIR:-/data/data/com.termux/files/usr/var/log}"

exec /data/data/com.termux/files/usr/share/termux-services/svlogger
