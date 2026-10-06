# Upstream sync: the patch series

The Android delta is kept here as nine patch files rather than as commits on top
of a merge. Upstream (`geph-official/geph5`) does not carry Android support and
is not expected to, so every release we would otherwise merge a whole upstream
tree into our history — most of which we never compile — purely to carry 107
changed lines.

## What the series covers, and what it does not

The series is only the changes to files **upstream owns**. Everything else in
this repo is ours outright and is never patched onto anything:

| Location | Owner |
|---|---|
| `android/**` — module, `service.sh`, `build-module.sh`, `gephctl`, `install.sh` | ours, no upstream counterpart |
| `patches/**`, `apply-patches.sh` | ours |
| `README.md`, `run-daemon.ps1` | ours (module docs) |
| `binaries/geph5-app/{Cargo.toml,src/{cli,client,platform,supervisor,manager}.rs}` | **patched** |
| `libraries/geph5-misc-rpc/{Cargo.toml,src/manager_control.rs}` | **patched** |

Current series: 9 patches, +171/−49 lines across 9 files. Each patch header
states what the change does, how fragile it is, and what it deliberately leaves
unfixed.

## Version pinning

A Geph *app* version is not a geph5 *crate* version. `gephgui-pkg` tag `v5.9.1`
(2026-09-27) pins the core by **git submodule** at `1f65e9e`, whose workspace
version is `0.4.2`. `patches/BASE` holds that commit; the series is written
against it. The pin history is the version ledger in
[MAINTENANCE.md](../MAINTENANCE.md).

When picking a base, resolve app version → submodule commit, not version strings:

```bash
git ls-tree <app-tag> geph5      # in gephgui-pkg, gives the submodule sha
git -C /path/to/geph5 show -s --format=%s <sha>
git -C /path/to/geph5 show <sha>:Cargo.toml | grep -m1 '^version'
```

The app tag sequence skips versions (`v5.9.0` does not exist), so do not infer a
base from version arithmetic.

## Updating to a new upstream release

The complete step-by-step procedure (including the fork-tip merge that must
precede regeneration) is in [MAINTENANCE.md](../MAINTENANCE.md). Condensed:

```bash
git fetch origin                       # in a geph5 checkout
git checkout <new-base-sha>
../apply-patches.sh --check .          # find out what breaks, change nothing
../apply-patches.sh .                  # or --3way to let git merge drifted context
patches/regenerate.sh <new-base-sha>   # regenerate the series against the new base
cargo check -p geph5-app -p geph5-client --target aarch64-linux-android
android/build-module.sh --arch all
```

If `--check` is clean, the series is already correct for the new base and only
`patches/BASE` needs bumping. If it rejects, work through the rejects, then
`regenerate.sh` to rewrite the diff hunks — the prose in `patches/headers/` is
preserved and is yours to edit.

## Patch order is deliberate

Sorted least-fragile first, so a reject on the large `platform.rs` patch does not
also cost you the one-line libc cfg:

1. `Cargo.toml` — adds `android` to the libc target cfg. A dependency table.
   Nothing can make this conflict unless the workspace is restructured.
2. `manager_control.rs` — dual-mode control-socket resolution through
   `android_state_dir()` (root → `/data/adb/geph5`, Termux → `$HOME/.geph5`,
   `GEPH5_STATE_DIR` override); turned `MANAGER_CONTROL_SOCK` from a const
   into a function.
3. `cli.rs` — the `register` enum variant.
4. `client.rs` — the `register` implementation.
5. `vpn.rs` — cfg widening so android reuses the linux backend.
6. `platform.rs` — **the fragile one**: 1946 lines, upstream has touched it 8
   times since 2025 (most recently 2026-08-24, in the 0.4.3 RNG refactor).
   Also carries the dual-install feature: state dirs follow
   `android_state_dir()` and `require_manager_privilege()` allows an
   unprivileged manager on Android.
7. `geph5-misc-rpc/Cargo.toml` — android libc dep for the euid probe; same
   shape as patch 1.
8. `supervisor.rs` — `PAC_ADDR` const → `pac_addr()` with `GEPH5_PAC_PORT`
   override, so a Termux install (12233) can listen beside the root module
   (12223).
9. `manager.rs` — one-line follower of 8 (PAC URL formatting).

7-9 were appended rather than renumbering 1-6 into a strict fragility order:
patches apply per-file and independently, so order affects review ergonomics,
not outcomes.

Patches apply independently per file but the crate only compiles with all nine
applied, since `client.rs` calls into `platform.rs`.

## Operational notes, learned the hard way

- **Never use `patch -p1`.** GNU patch applies with fuzz, accepting shifted
  context and leaving a tree that compiles while gating on the wrong platform.
  `apply-patches.sh` uses `git apply` throughout, which lands exactly or fails.
- **`--3way` needs the index to match the worktree.** It reconstructs "ours"
  from the index, so unstaged drift makes it abort with a misleading
  `does not match index`. The script warns when it detects this; stage or commit
  first for a clean merge.
- **`git apply --check --3way` does not predict conflicts.** It reports success
  because it expects to be able to reconstruct and merge, so `--check` is only
  meaningful without `--3way`. The script therefore checks in plain mode and
  applies-and-reads-the-result in 3way mode.
- **Conflicts are left in the tree on purpose.** A missing `platform.rs` patch
  yields a binary that gates on the wrong target OS — it compiles, and then does
  the wrong thing at runtime. Resolve before building.
- **The script is idempotent.** A patch already present is reported as
  `skip … (already applied)`, so re-running after a mid-series failure is safe.

## Known Android limitations (not patch bugs)

- **Full-tunnel VPN does not come up on Android.** `vpn.rs` requires a service
  user before calling `backend::setup`, and `ensure_service_user()` returns
  `None` on Android because there is no `useradd`. The nftables kill-switch is
  also unavailable (no `nft`). Proxy (SOCKS5/HTTP) and auto-proxy mode do not go
  through this path and work fully.
- **`register-manager` / `unregister-manager` error on Android** — they are
  systemd/launchd/Scheduled Task paths. The module autostarts via `service.sh`.

Both are pre-existing and orthogonal to the sync model; fixing them is real work,
not a cfg tweak.

## Verifying the series is faithful

The strong check: apply the series to a pristine checkout of the base and
confirm the nine files match the built tree byte for byte, `Cargo.lock`
included.

```bash
git worktree add --detach /tmp/verify <base-sha>
./apply-patches.sh /tmp/verify
diff -rq --exclude=.git . /tmp/verify   # only android/, patches/, docs should differ
```

That equality is what lets the series stand in for a merge: identical sources and
an identical lock file mean an identical build, so there is no need to rebuild to
re-prove it.