# Geph5 as a Termux service (termux-services / runit, no root)

This is the **unprivileged** way to run geph5 on Android: the manager runs as
the Termux user, supervised by runit (`termux-services`), starting at boot via
Termux:Boot. No KernelSU/Magisk module, no `su`, no root at all.

The same binary also supports the root-module install; the two are told apart
at runtime by euid: root → data in `/data/adb/geph5`, unprivileged → data in
`~/.geph5`. Both installs can even run side by side — their ports differ:

| Listener   | Root module | Termux service |
|------------|-------------|----------------|
| SOCKS5     | 127.0.0.1:9909  | 127.0.0.1:**9929**  |
| HTTP proxy | 127.0.0.1:9910  | 127.0.0.1:**9930**  |
| PAC        | 127.0.0.1:12223 | 127.0.0.1:**12233** |
| RPC control | unix socket `/data/adb/geph5/control.sock` | unix socket `~/.geph5/control.sock` |

## Build flow: cross-compile on the desktop, package on the phone

Termux's own packages are all cross-compiled on x86_64 servers
(termux-packages + the `termux/package-builder` Docker image) — nobody
compiles on a phone, and neither should you. The deb flow mirrors that:

1. **Desktop** — cross-compile once for every arch you ship:

   ```bash
   ./android/build-module.sh                # aarch64 + x86_64 via the NDK
   # binaries land in upstream/target/<arch>-linux-android/release/
   ```

2. **Push** the matching arch to the phone and stage them where
   `build-deb.sh --skip-build` looks:

   ```bash
   adb push upstream/target/aarch64-linux-android/release/geph5 \
             /data/local/tmp/geph5.cross
   adb push upstream/target/aarch64-linux-android/release/geph5-client \
             /data/local/tmp/geph5-client.cross
   # as the termux user, into <repo>/upstream/target/release/:
   cp /data/local/tmp/geph5.cross       ~/g5/upstream/target/release/geph5
   cp /data/local/tmp/geph5-client.cross ~/g5/upstream/target/release/geph5-client
   ```

3. **Phone (Termux)** — package and install, no compilation:

   ```bash
   bash ./android/termux/build-deb.sh --skip-build
   pkg install ./android/dist/geph5_*_aarch64.deb
   ```

The NDK binaries are bionic-linked like Termux's own and run unmodified
(verified on-device). The on-device `cargo build` path below remains for
development; note that on a censored network `cargo fetch` is the bottleneck
(crates.io through a slow exit), so prefer the cross flow.

Android has no `/usr/bin/env`, so the repo scripts with `#!/usr/bin/env bash`
shebangs must be invoked as `bash <script>` (the in-repo callers do).

## Install

### Option A: install the .deb (recommended)

```bash
# on-device, one command (pulls in termux-services automatically):
pkg install ./geph5_<version>_aarch64.deb
# build the deb yourself from a checkout:
./android/termux/build-deb.sh            # add --skip-build to reuse binaries
```

Removal: `apt remove geph5` (keeps `~/.geph5`), `apt purge geph5` (deletes it).
Upgrades (`pkg install` a newer deb) stop/restart the service automatically.

### Option B: install from source (development)

```bash
pkg install rust termux-services   # once
# also install the Termux:Boot app (F-Droid/Play) and open it once

./android/termux/install.sh
```

Both paths produce the same layout; the deb is just the packaged form of
`install.sh` (maintainer scripts mirror its seeding/enable/start logic).

The installer builds natively (aarch64), installs `geph5`, `geph5-client`,
`gephsvc` into `$PREFIX/bin`, seeds `~/.geph5/settings.json` with the ports
above, installs the sv service under `$PREFIX/sv/geph5`, enables it, and
starts the manager.

> **Naming:** this install's control script is `gephsvc`, deliberately distinct
> from `gephctl` — the su-based wrapper the root module deploys for controlling
> the root instance. Both can coexist in `$PREFIX/bin`.

Useful options:

```bash
./android/termux/install.sh --skip-build          # reuse target/release
./android/termux/install.sh --migrate-from-module # copy settings+cache from
                                                  # /data/adb/geph5 (needs su)
./android/termux/install.sh --socks5-port 1080 --http-port 8080 --pac-port 25000
```

## Usage

```bash
gephsvc login                # once, before first connect
gephsvc connect              # bring the tunnel up
gephsvc status               # service + connection state
gephsvc exit-constraint set --country us
gephsvc logs -n 50           # engine logs
gephsvc manager-logs -f      # manager log (svlogd), follow
gephsvc start / stop / restart / enable / disable   # sv lifecycle
```

Anything not listed is forwarded to the `geph5` CLI verbatim.

## How supervision works

- `$PREFIX/sv/geph5/run` execs `geph5 manager` with `GEPH5_PAC_PORT` set;
  runit restarts it if it crashes, `sv stop` sends SIGTERM (clean shutdown;
  the engine child follows via PDEATHSIG).
- `$PREFIX/sv/geph5/log/run` pipes stdout/stderr into svlogd
  (`$PREFIX/var/log/sv/geph5/current`, auto-rotated).
- At boot Termux:Boot runs `~/.termux/boot/*`, which starts
  `service-daemon` (runsvdir) over `$SVDIR`; enabled services come up with it.
  The manager holds no wake lock itself; add `termux-wake-lock` to a boot
  script if Android aggressively kills Termux.

## Data & logs

- State: `~/.geph5` (`settings.json`, `cache/`, `run/*.sock`)
- Manager log: `$PREFIX/var/log/sv/geph5/current`

## Limitations

- VPN (full-tunnel) mode is unsupported in this install — it needs
  CAP_NET_ADMIN and Android has no `nft` anyway; the root module cannot do it
  either. Proxy mode (SOCKS5/HTTP + PAC) is fully supported: point apps at
  `127.0.0.1:9929` / `127.0.0.1:9930`.
- If you migrated from the root module, disable it (`KernelSU manager →
  modules → geph5 → remove`) so the two managers don't race.

## Uninstall

```bash
./android/termux/uninstall.sh           # keeps ~/.geph5
./android/termux/uninstall.sh --purge   # also deletes ~/.geph5
```
