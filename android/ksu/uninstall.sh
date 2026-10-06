#!/system/bin/sh
# Geph5 KernelSU uninstall: stop the manager and delete its data.

# Kill only root-owned processes; a Termux-user install may be running side
# by side and is not ours to kill.
for pid in $(pgrep -x geph5 2>/dev/null); do
    [ "$(stat -c %u "/proc/$pid" 2>/dev/null)" = "0" ] && kill -TERM "$pid" 2>/dev/null
done
for pid in $(pgrep -x geph5-client 2>/dev/null); do
    [ "$(stat -c %u "/proc/$pid" 2>/dev/null)" = "0" ] && kill -TERM "$pid" 2>/dev/null
done
rm -rf /data/adb/geph5
echo "[geph5] removed; data at /data/adb/geph5 deleted."

exit 0
