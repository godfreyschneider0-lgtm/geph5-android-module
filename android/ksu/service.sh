#!/system/bin/sh
# Geph5 KernelSU late_start service: start the geph5 manager as root at boot.

MODDIR=${0%/*}
DATA=/data/adb/geph5

mkdir -p "$DATA/logs" "$DATA/run"

# Stop any stale manager left over from a previous boot or module upgrade.
if [ -f "$DATA/run/manager.pid" ]; then
    old_pid=$(cat "$DATA/run/manager.pid" 2>/dev/null)
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
        kill -TERM "$old_pid" 2>/dev/null
    fi
    rm -f "$DATA/run/manager.pid"
fi
pkill -TERM -f 'geph5 manager' 2>/dev/null
sleep 2

# Rotate the log if it grew past 4 MiB.
if [ -f "$DATA/logs/manager.log" ]; then
    size=$(wc -c < "$DATA/logs/manager.log" 2>/dev/null)
    if [ -n "$size" ] && [ "$size" -gt 4194304 ]; then
        mv -f "$DATA/logs/manager.log" "$DATA/logs/manager.log.old" 2>/dev/null
    fi
fi

# Start the manager (the engine child dies with it via PDEATHSIG).
nohup "$MODDIR/geph5" manager >>"$DATA/logs/manager.log" 2>&1 &
echo $! >"$DATA/run/manager.pid"

# Wait up to 15 s for the control socket to appear.
i=0
while [ "$i" -lt 15 ]; do
    if [ -S "$DATA/control.sock" ]; then
        break
    fi
    sleep 1
    i=$((i + 1))
done

if [ -S "$DATA/control.sock" ]; then
    echo "[geph5] manager up (socket ready)"
else
    echo "[geph5] WARNING: control socket not ready after 15s, see $DATA/logs/manager.log"
fi

exit 0
