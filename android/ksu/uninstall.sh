#!/system/bin/sh
# Geph5 KernelSU uninstall: stop the manager and delete its data.

pkill -TERM -f 'geph5 manager' 2>/dev/null
pkill -TERM -f 'geph5-client' 2>/dev/null
rm -rf /data/adb/geph5
echo "[geph5] removed; data at /data/adb/geph5 deleted."

exit 0
