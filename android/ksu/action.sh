#!/system/bin/sh
# Geph5 KernelSU action button: toggle the connection.

MODDIR=${0%/*}

state=$("$MODDIR/geph5" status >/dev/null 2>&1 && "$MODDIR/geph5" status 2>/dev/null | head -n 1)

case "$state" in
    *"State: connected"*)
        "$MODDIR/geph5" disconnect >/dev/null 2>&1
        echo "Geph5 disconnected."
        ;;
    *"State: connecting"*)
        echo "Geph5 is already connecting."
        ;;
    *"State: disconnected"*)
        "$MODDIR/geph5" connect >/dev/null 2>&1
        echo "Geph5 connecting..."
        ;;
    *)
        "$MODDIR/geph5" connect >/dev/null 2>&1
        echo "Geph5 connecting... (manager not reachable - check the module is active and the device has booted)"
        ;;
esac

exit 0
