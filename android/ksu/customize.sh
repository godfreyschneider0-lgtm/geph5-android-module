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

# Ensure binaries and scripts are executable (some root managers strip +x).
ui_print "- Setting permissions..."
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/geph5" 0 0 0755
set_perm "$MODPATH/geph5-client" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755

ui_print "Installing Geph5 anti-censorship network module..."
ui_print "Reboot required. After reboot:"
ui_print "- Use the action button in the KernelSU manager app to toggle the connection"
ui_print "- Or install gephctl in Termux for full control (see README)"
ui_print "- Data lives at /data/adb/geph5"

exit 0
