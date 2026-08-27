#!/system/bin/sh
# Geph5 KernelSU installer: abort on non-arm64 devices, print usage info.

ABI=$(getprop ro.product.cpu.abi)

case "$ABI" in
    arm64-v8a)
        : ;;
    *)
        case "$ARCH" in
            *arm64*)
                : ;;
            *)
                abort "! geph5 module only supports arm64-v8a devices (found: $ABI)"
                ;;
        esac
        ;;
esac

ui_print "Installing Geph5 anti-censorship network module..."
ui_print "Reboot required. After reboot:"
ui_print "- Use the action button in the KernelSU manager app to toggle the connection"
ui_print "- Or install gephctl in Termux for full control (see README)"
ui_print "- Data lives at /data/adb/geph5"

exit 0
