#!/system/bin/sh
# Geph5 KernelSU action button: toggle the connection.

MODDIR=${0%/*}

state=$("$MODDIR/geph5" status 2>/dev/null | head -n 1)

case "$state" in
    *"State: connected"*)
        "$MODDIR/geph5" disconnect 2>/dev/null
        echo "Geph5 disconnected."
        ;;
    *"State: connecting"*)
        echo "Geph5 is already connecting."
        ;;
    *)
        "$MODDIR/geph5" connect 2>/dev/null
        case "$state" in
            State:*)
                echo "Geph5 connecting…"
                ;;
            *)
                echo "Geph5 connecting… (manager not reachable - check the module is active and the device has booted)"
                ;;
        esac
        ;;
esac

exit 0
