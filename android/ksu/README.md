# Geph5 KernelSU Module

## Overview
A KernelSU module packaging of Geph5, an anti-censorship VPN/proxy. Runs
`geph5 manager` as root at boot to manage the connection automatically.

## Requirements
- KernelSU (or compatible Magisk / APatch)
- arm64-v8a devices, Android 7.0+
- Rooted

## Install
1. KernelSU manager -> Modules -> Install from storage -> pick the zip -> reboot.
2. Or from the repo: `./android/install.sh <zip>` (requires adb).

## Usage
- After reboot, tap the module's action button in the KernelSU manager to toggle the
  connection.
- For full control, install gephctl in Termux (see android/termux-gephctl.sh):
  `gephctl status / connect / disconnect`, etc.
- Or run the CLI directly via su: `su -c "/data/adb/modules/geph5/geph5 status"`.

## Data & Logs
- Working dir: /data/adb/geph5 (settings.json, control socket control.sock, runtime
  sockets run/...)
- Manager log: /data/adb/geph5/logs/manager.log

## Caveats
- Full-tunnel VPN mode relies on `ip`/`nft`; Android lacks `nft`, so the nftables
  kill-switch parts may be unavailable. Proxy (SOCKS5/HTTP) mode is fully supported.
- You must log in once before you can connect.
- `register-manager` only applies to desktop platforms (systemd/launchd/Scheduled
  Task) and errors out on Android; this module autostarts via `service.sh`.

## Uninstall
Remove the module in the KernelSU manager. The uninstall script stops the manager and
deletes /data/adb/geph5 entirely.

## Build your own zip
Run `./android/build-module.sh` from the repo root.
