# Geph5 Android Module

Geph5 as an Android system module (KernelSU / Magisk / APatch). At boot it runs
`geph5 manager` as root and manages the connection automatically.

Geph5 is an anti-censorship VPN/proxy client. Relative to Geph4 it is a major
rewrite that aims to **simplify and massively clean up the design**.

## Quick start

### Build the module zips (arm64 + x64)

```bash
./android/build-module.sh                  # build both architectures
./android/build-module.sh --arch arm64     # arm64 only
./android/build-module.sh --skip-build     # reuse binaries, repackage only
```

Artifacts land in `android/dist/geph5-ksu-v0.3.9-{arm64,x64}.zip`.

### Install (three ways)

1. **Root manager "Install from storage"**: pick the arch-matched zip on the
   KernelSU / Magisk / APatch module page, install, reboot.
2. **One-shot ADB install** (auto-detects ksud / magisk / apd):

   ```bash
   ./android/install.sh android/dist/geph5-ksu-v0.3.9-arm64.zip
   ```

3. **Magisk CLI**: `adb push ... /data/local/tmp/ && adb shell su -c 'magisk --install-module /data/local/tmp/geph5-ksu.zip'`

Flashing the module **auto-deploys the `gephctl` control script**: if Termux is
detected it is installed to `$PREFIX/bin/gephctl`, otherwise it falls back to
`/data/local/tmp/gephctl`.

### Usage

After reboot `service.sh` auto-starts the manager as root. Pick any of:

- **`gephctl` in Termux** (thin shell that forwards geph5 subcommands, no manual
  `su -c`):

  ```bash
  gephctl status                                    # manager + connection state
  gephctl connect / disconnect                      # connect / disconnect
  gephctl exit-constraint set --country us          # pick an exit
  gephctl vpn on | proxy on                         # VPN / proxy mode
  gephctl logs -n 50                                # engine logs
  gephctl start / stop / restart                    # service lifecycle
  gephctl login
  ```

- **CLI (su)**: `su -c "/data/adb/modules/geph5/geph5 status"`
- **Manager action button**: the module's "action" button in the
  KernelSU / Magisk / APatch manager toggles the connection.

Full details: [android/ksu/README.md](android/ksu/README.md).

## Data & logs

- Working dir: `/data/adb/geph5` (settings `settings.json`, control socket
  `control.sock`, runtime `run/`)
- Manager log: `/data/adb/geph5/logs/manager.log`

## Notes

- Full-tunnel VPN relies on `ip`/`nft`; Android lacks `nft`, so the nftables
  kill-switch is unavailable. Proxy (SOCKS5/HTTP) + auto-proxy mode is fully
  supported.
- You must log in once (`gephctl login`) before you can connect.
- `register-manager` only applies to desktop platforms (systemd/launchd/Scheduled
  Task) and errors out on Android; this module autostarts via `service.sh`.

---

# Geph5

Key architectural differences of Geph5 versus Geph4:

## Overview

- `sosistab2`, or anything similar that builds a reliable transport on unreliable
  pipes, is no longer used. Obfuscated transports must themselves provide reliable
  transport, i.e. streams multiplexed over TCP, not packets/UDP.
- The client no longer has complex logic for intelligently hot-swapping pipes. A
  session is started and used until it breaks, then another is started, etc. With
  fast enough session creation the only visible difference is proxied TCP
  connections reset, which most applications handle gracefully.
- The central authentication server is called the **broker** (not the binder). It
  uses a simple JSON-RPC API without end-to-end encryption; integrity-critical
  responses carry ed25519 signatures.
- The broker communicates with bridges and exits to set up routes, eliminating the
  complex `(bridges) × (exits)` communication pattern.
- VPN mode is supported by tunneling through stream (socks5) mode, with support for
  intercepting traffic tun2socks-style.
- Config files are used pervasively rather than long command-line argument strings.
- GUI clients are written in Rust and call protocol libraries directly; no webviews.

## License

The code is generally licensed under **MPL 2.0**. Low-level libraries useful to a
wide variety of projects (e.g. the `sillad` framework) are generally licensed under
the ISC license.

## Code organization

Geph5 uses a Cargo workspace ("monorepo") layout:

- `libraries/`: library crates that may depend on each other; all are released to
  crates.io.
- `binaries/`: binary crates.
  - `geph5-client`
  - `geph5-exit`
  - `geph5-bridge`
  - `geph5-broker`
- `android/`: Android system module (build, install, Termux control script,
  `service.sh` autostart).
