# Geph5 Android Module

Geph5 on Android, two install modes from one source tree:

1. **Termux service (no root)** — `geph5 manager` runs as the Termux user
   under termux-services (runit) supervision, autostarting via Termux:Boot.
   Install as a deb (`./android/termux/build-deb.sh` on-device, then
   `pkg install ./android/dist/geph5_*.deb`, deps auto-resolved) or from
   source. See [android/termux/README.md](android/termux/README.md).

2. **KernelSU / Magisk / APatch root module** — `geph5 manager` runs as root
   at boot via `service.sh`; controlled with `gephctl` through `su`.

Both installs can even run side by side on one device: their ports and data
dirs differ (SOCKS5 9909/9929, HTTP 9910/9930, PAC 12223/12233;
`/data/adb/geph5` vs `~/.geph5`). One binary serves both, told apart at
runtime by euid.

Geph5 is an anti-censorship VPN/proxy client. This repository contains **only
the Android packaging**: the geph5 Rust source itself is the `upstream/`
submodule (geph-official/geph5), and our changes to it live in `patches/`.

## Quick start

### Root module (cross-compiled on your desktop)

```bash
git clone --recurse-submodules <this repo>
cd geph5-android-module
./android/build-module.sh                # applies patches, builds, packages both arches
```

If you cloned without `--recurse-submodules`:

```bash
git submodule update --init upstream
```

Artifacts land in `android/dist/geph5-ksu-v<geph5-version>-{arm64,x64}.zip`.

### Termux deb (built on-device)

```bash
pkg install rust dpkg termux-services   # once; also install the Termux:Boot app
git clone --recurse-submodules <this repo> && cd geph5-android-module
./android/termux/build-deb.sh           # applies patches, builds natively, packs the deb
pkg install ./android/dist/geph5_*.deb
gephsvc login && gephsvc connect         # socks5 127.0.0.1:9929, http 127.0.0.1:9930
```

### Build options

```bash
./android/build-module.sh                  # both architectures
./android/build-module.sh --arch arm64     # arm64 only
./android/build-module.sh --skip-build     # repackage existing binaries
./android/build-module.sh --ndk /path/to/ndk
```

### Install (three ways)

1. **Root manager "Install from storage"**: pick the arch-matched zip on the
   KernelSU / Magisk / APatch module page, install, reboot.
2. **One-shot ADB install** (auto-detects ksud / magisk / apd):

   ```bash
   ./android/install.sh android/dist/geph5-ksu-v0.4.2-arm64.zip
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

## Repository layout

| Path | What it is |
|---|---|
| `android/` | the module: build, install, `service.sh`, `gephctl`, zip templates |
| `android/termux/` | the no-root Termux install: deb packaging, `gephsvc`, runit service |
| `upstream/` | geph5 submodule, pinned; **not** ours to edit directly |
| `patches/` | our changes to upstream files, as a patch series |
| `apply-patches.sh` | applies the series to `upstream/`; idempotent |
| `patches/BASE` | the upstream commit the series is written against |

### Syncing a new upstream release

Full step-by-step walkthrough: [MAINTENANCE.md](MAINTENANCE.md). Summary:

We do not merge upstream. `upstream/` stays pristine at the pinned commit, and
our delta is re-applied on top as nine patches ordered least-fragile first.

```bash
git -C upstream fetch origin
git -C upstream checkout <new-release-commit>

./apply-patches.sh --check upstream/     # does the series still apply?
./android/build-module.sh               # applies and builds
patches/regenerate.sh <new-release-commit>
```

Full rationale, the patch ordering, and the operational traps are in
[patches/README.md](patches/README.md). Read that before syncing.

### Which version is this?

A Geph *app* release is not a geph5 *crate* version. `gephgui-pkg` tag `v5.9.1`
pins the core by submodule at `1f65e9e`, whose workspace version is `0.4.2` —
so the module zip is named `v0.4.2` even though it ships Geph 5.9.1. This
module tracks stable app tags, never upstream `master`. The authoritative
current pin and its history are the version ledger in
[MAINTENANCE.md](MAINTENANCE.md); to resolve an app version to a base commit
yourself, see [MAINTENANCE.md](MAINTENANCE.md) §5, Step 0.

## Notes and limitations

- **Full-tunnel VPN does not work on Android.** `vpn.rs` requires a service user
  before setting up the backend, and Android has no `useradd`; the nftables
  kill-switch is also unavailable (no `nft`). **Proxy (SOCKS5/HTTP) and
  auto-proxy mode are fully supported** and are what this module is for.
- You must log in once (`gephctl login`) before you can connect. `gephctl
  register` creates a free account by solving a proof-of-work puzzle.
- `register-manager` / `unregister-manager` only apply to desktop platforms
  (systemd/launchd/Scheduled Task) and error out on Android; this module
  autostarts via `service.sh`.
- Data lives in `/data/adb/geph5`. Uninstalling the module removes the binaries;
  use `gephctl` or delete that directory to remove credentials and logs.

## License

The geph5 source in `upstream/` is licensed MPL-2.0 (libraries such as `sillad`
are ISL); see `upstream/LICENSE`. The module files in `android/` are part of this
distribution under the same terms.