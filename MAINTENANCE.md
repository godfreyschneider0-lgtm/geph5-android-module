# Maintenance guide — the patch series and upstream syncs

This is the operational manual for `patches/` and `apply-patches.sh`: how to keep
the series healthy day to day, and exactly what to do when a new geph5 release
lands upstream. Design rationale (why a patch series instead of a merge) lives in
[`patches/README.md`](patches/README.md); user-facing module docs live in the
[top-level README](README.md).

Everything here is mechanical on purpose. If a step ever requires hand-editing a
patch hunk, that step is wrong — re-derive instead (§6).

## 1. The model in one screen

```
                    this repo (ours)                     geph-official/geph5
 ┌────────────────────────────────────────────┐    ┌──────────────────────────┐
 │ android/         module scripts, templates │    │ pristine history         │
 │ patches/         9 patches + BASE + prose  │    │ (never edited by us)     │
 │ apply-patches.sh applies series ───────────┼───▶│ upstream/ submodule      │
 │ patches/regenerate.sh  re-exports series   │    │ pinned at patches/BASE   │
 └────────────────────────────────────────────┘    └──────────────────────────┘
```

| Thing | Owner | Notes |
|---|---|---|
| `android/**`, `patches/**`, `apply-patches.sh`, READMEs | ours outright | never patched onto anything |
| `binaries/geph5-app/{Cargo.toml,src/{cli,client,platform,supervisor,manager}.rs}`, `libraries/geph5-misc-rpc/{Cargo.toml,src/manager_control.rs}` | upstream's files, **patched** | the nine files the series touches |
| `upstream/` | upstream, pristine | build input; stays at the commit named by `patches/BASE` |

Two trees matter and they are not the same thing:

- **`upstream/` (the submodule)** — pristine upstream at the pinned commit;
  `apply-patches.sh` writes our delta into its *working tree* to produce a
  buildable tree. It is scratch: reset it any time (§4).
- **The fork history of this repo** — the permanent record of "upstream + our
  delta". `patches/regenerate.sh` *exports* the series from it. This is the
  source of truth for patch content; see §3 before your first sync.

## 2. Anatomy of the series

Six patches carry the original Android support; three more (0007-0009)
carry the dual-install feature (an unprivileged Termux service alongside
the root module). One upstream file each, applied in filename order —
sorted least-fragile first, so a reject on the big `platform.rs` patch never
costs you the one-line `Cargo.toml` cfg:

| # | Patch | What it does | Fragility |
|---|---|---|---|
| 1 | `geph5-app-cargo-libc-android` | libc target cfg gains `android` | negligible |
| 2 | `manager-control-android-sock` | dual-mode socket resolution via `android_state_dir()` (euid/HOME/`GEPH5_STATE_DIR`) | low |
| 3 | `cli-register-subcommand` | `register` enum variant | low |
| 4 | `client-register-command` | `register` implementation (PoW signup) | low |
| 5 | `vpn-android-cfg` | cfg widening so android reuses the linux backend | medium |
| 6 | `platform-android` | real Android behaviour: state paths, no service user, unprivileged manager allowed, HOME-less KDE skip | **high** — 1946-line file, upstream touches it monthly |
| 7 | `misc-rpc-cargo-libc-android` | android libc dep for the euid probe | negligible |
| 8 | `supervisor-pac-port` | `PAC_ADDR` const → `pac_addr()` with `GEPH5_PAC_PORT` override | low |
| 9 | `manager-pac-caller` | one-line follower of 8 in `manager.rs` | negligible |

Each `patches/NNNN-*.patch` file is two concatenated parts:

1. **Header** (everything above the `---` line) — human-written prose: what the
   change does, how fragile, what it deliberately leaves unfixed. Masters live
   in `patches/headers/*.header`; `regenerate.sh` copies them verbatim and never
   overwrites them.
2. **Diff** (everything below `---`) — machine-derived `git diff` output for
   exactly one file. Never edit this by hand; it is regenerated (§6).

`patches/BASE` holds the upstream commit the series is written against.

Invariants — breaking these is how the model rots:

- `git apply` only, never GNU `patch -p1`. GNU patch applies with *fuzz*,
  silently accepting drifted context and leaving a tree that compiles while
  gating on the wrong platform. `git apply` lands exactly or fails loudly.
- One file per patch; numbering = application order = fragility rank.
- Patch hunks are derived output, not source. Change content via §6, never via
  the `.patch` file.
- The crate only compiles with **all nine** applied — `client.rs` calls into
  `platform.rs`. A half-applied series is worse than none: it builds and then
  misbehaves at runtime.

## 3. Where patch content comes from — read before your first sync

`patches/regenerate.sh <base>` produces each patch as:

```bash
git diff <base>..HEAD -- <that patch's file>
```

run **in this repo**, against the commit currently checked out. Consequences:

1. **HEAD must be a full-tree commit** whose tree is "the new base plus our
   delta" — call it the *fork tip*. Today that is `main` at `7f7cf1d`.
2. **Never bump BASE and regenerate before absorbing the new base into the fork
   tip.** If HEAD still carries the old base, `git diff <new-base>..HEAD`
   includes *reversals of upstream's changes* — verified: regenerating against
   `55dcced` with the current tip produces patches that downgrade
   `geph5-broker-protocol` 0.4.3 → 0.4.0 and friends. The series would apply,
   build, and silently revert upstream's release.
3. **A tree-less HEAD breaks regeneration.** As of this writing there is a
   *staged but uncommitted* conversion that deletes `binaries/`, `libraries/`,
   `Cargo.toml`, … from the tip and keeps only `upstream/` as a submodule
   (233 files, −157k lines). If that diff is committed as-is, rule 1 stops
   holding: `git diff <base>..HEAD -- <path>` degenerates to whole-file
   deletions and `regenerate.sh` exports garbage. Pick one of two clean states
   before syncing:

   - **Option A (keep the submodule tip).** Commit the conversion, then
     `git branch fork 7f7cf1d` — the last full-tree commit. All series work
     (merges, edits, regeneration) happens on `fork`; publish only `patches/`
     back to `main`:

     ```bash
     git switch fork
     # ...sync or edit, regenerate...
     git switch main
     git checkout fork -- patches
     git add patches && git commit
     ```

   - **Option B (keep the full-tree tip).** Drop the staged conversion
     (`git restore --staged . && git checkout -- .`), delete `.gitmodules`,
     and add `/upstream/` to `.gitignore` so the pristine clone is just a
     plain ignored directory. `main` remains the fork tip.

   Either is fine; what is not fine is regenerating while the checkout is
   mid-transition. `git status` must be clean before §5 step 3.

## 4. Day-to-day cheat sheet

```bash
./apply-patches.sh --check upstream/      # does the series still apply cleanly?
./apply-patches.sh upstream/              # apply (idempotent; re-run after failures)

git -C upstream status -s                 # afterwards: exactly the 9 files, modified

cd upstream && cargo check -p geph5-app -p geph5-client \
    --target aarch64-linux-android        # quick compile gate (needs NDK linker setup)

./android/build-module.sh [--arch arm64]  # full build; applies the series itself
                                         # and refuses to build an unpatched tree

git -C upstream reset --hard HEAD         # reset the build tree back to pristine
git -C upstream clean -fd                 # drop untracked; ignored dirs (target/) survive
```

Idempotency works by reverse-checking: a patch where
`git apply --check --reverse` succeeds is reported `skip … (already applied)`,
so re-running after a mid-series failure resumes instead of duplicating.

Module versioning is derived, not typed: `VERSION` comes from
`upstream/Cargo.toml`'s workspace version and `VERSIONCODE` from
`git -C upstream rev-list --count HEAD` — both follow the submodule checkout,
so a synced release needs no manual version edits. The one record a sync must
update by hand is the app-tag mapping: the version ledger at the end of §5.

## 5. Syncing a new upstream release

### Step 0 — resolve the release to a base commit

**Policy — track stable app releases, never upstream `master`.** The base is
always the geph5 commit pinned by the newest stable `gephgui-pkg` tag, so this
module ships the same core the official app ships. Master can look tempting —
0.4.3 (`55dcced`) even applies 6/6 cleanly — but no app release has shipped it;
resist unless a specific fix is required, and then say so in the ledger below.

A Geph *app* version is not a geph5 *crate* version, and app tags skip numbers
(`v5.9.0` does not exist). Resolve the newest tag to a base commit via the
submodule pin, not arithmetic:

```bash
# newest stable tag (no clone needed)
git ls-remote --tags https://github.com/geph-official/gephgui-pkg.git | tail -5

# in a gephgui-pkg checkout of that tag: app tag -> geph5 submodule sha
# (this is how the current base was resolved: v5.9.1 -> 1f65e9e -> 0.4.2)
git ls-tree v5.9.1 geph5

# in any geph5 checkout: what is that sha?
git show -s --format='%h %s' <sha>
git show <sha>:Cargo.toml | grep -m1 '^version'
```

### Step 1 — fetch, and point the build tree at the new base

```bash
git fetch official                  # main repo: brings new upstream commits in
                                    # for the fork merge in step 3
git -C upstream fetch origin
git -C upstream checkout <new-base>
```

### Step 2 — triage

```bash
./apply-patches.sh --check upstream/
```

- `6/6 ok` → fast path; the merge in step 3 will almost certainly be
  conflict-free (the two checks agree: series clean against `55dcced` ⟺
  `git merge-tree` clean for the same pair).
- any `REJECT` → conflict path; the merge in step 3 will conflict in exactly
  those files.

Either way you still perform step 3 — see the §3 rule.

### Step 3 — absorb the base into the fork tip (mandatory, both paths)

On the fork tip (`main` today, or the `fork` branch under Option A), with a
clean `git status`:

```bash
git switch main                      # or: git switch fork
git merge <new-base>
```

- **Fast path:** the merge lands by itself. Commit it.
- **Conflict path:** resolve each conflict by keeping *our cfg arms merged with
  their refactor* — e.g. upstream's new `any(target_os = "linux", …)` must gain
  `target_os = "android"`, not pick a side. Then:

  ```bash
  cd upstream && cargo check -p geph5-app -p geph5-client \
      --target aarch64-linux-android   # the resolved tree must compile
  ```

  Commit the merge. This commit is the new fork tip — the permanent record of
  "new base + our delta".

Do not skip this because the build already works from `upstream/`. The fork tip
is what the series is exported from; letting it drift one release means the
next `regenerate.sh` silently exports reversals (§3, consequence 2).

### Step 4 — re-export the series

```bash
./patches/regenerate.sh <new-base>
git diff -- patches/
```

- Fast path: nine lines of `unchanged`, only `patches/BASE` moves. Review, done.
- Conflict path: the patches whose files drifted get new hunks; headers are
  preserved verbatim. Read the diff — it is the reviewable form of the merge
  you just did.

### Step 5 — build and verify

```bash
./android/build-module.sh             # VERSION/VERSIONCODE follow the checkout
```

Optionally prove the series faithful (§7) before shipping. Artifacts land in
`android/dist/geph5-ksu-<version>-{arm64,x64}.zip`.

### Step 6 — record the sync

Module artifacts need nothing here: `module.prop` and the zip names derive
from the submodule checkout automatically (§4). Two human records do:

1. Append a row to the version ledger below.
2. Refresh the current-pin sentences in `README.md` ("Which version is
   this?") and `patches/README.md` ("Version pinning") to the new tag/sha/version.

The mechanical part of the row:

```bash
base=$(cat patches/BASE)
ver=$(git -C upstream show "$base":Cargo.toml \
        | sed -n 's/^version = "\(.*\)"/\1/p' | head -n1)
echo "base=$base crate=$ver"    # add the app tag from Step 0 by hand
```

### Version ledger

Every completed sync appends one row. Newest last. If a base was ever taken
from something other than a stable app tag, say so and why in a note.

| Date | App tag | Base (`patches/BASE`) | Crate version | Module zip |
|---|---|---|---|---|
| 2026-10-06 | v5.9.1 | `1f65e9e` | 0.4.2 | `geph5-ksu-v0.4.2` |

## 6. Changing the series itself

All changes funnel through the same loop: **change the content in the fork-tip
tree, commit, regenerate.** The `.patch` files are output, never input.

- **Change a patch's behaviour** — edit the file in the fork-tip checkout
  (working tree has the full tree), compile-check, commit, then
  `./patches/regenerate.sh` (no argument = current BASE). Review
  `git diff -- patches/`.

- **Add a new upstream file to the series** — three pieces, all required:
  1. write the prose header `patches/headers/<stem>.header` (Subject line +
     body, mirroring the existing six);
  2. register the file in the `TARGETS` map inside `patches/regenerate.sh` —
     a patch whose file is not in `TARGETS` will never materialize;
  3. make the change in the fork-tip tree, commit, `./patches/regenerate.sh`.
  Choose the `00NN-` number to match the new patch's fragility rank, since
  numbering is application order. Renumbering the later patches (renames +
  headers together, `Subject: [PATCH n/N]` lines included) is the pure form;
  appending after the current last patch is acceptable when the renumber
  churn isn't worth it — patches apply per-file and independently, so order
  affects review ergonomics, not outcomes. That is how 0007-0009 were added.

- **Edit prose only** — edit `patches/headers/<stem>.header`, then re-run
  `./patches/regenerate.sh` to propagate it into the `.patch` file.

- **Remove a patch** — revert its change in the fork-tip tree, commit, delete
  the `.patch`, its header, and its `TARGETS` entry, then regenerate and
  confirm the other five report `unchanged`.

## 7. Proving the series is faithful

The strong check: the pinned tree plus the series must equal the built tree
byte for byte, `Cargo.lock` included. Identical sources and lock mean an
identical build, so equality here substitutes for a re-build.

```bash
git -C upstream reset --hard HEAD && git -C upstream clean -fd   # pristine
./apply-patches.sh upstream/                                     # series applied

git -C upstream worktree add --detach /tmp/verify "$(cat patches/BASE)"
./apply-patches.sh /tmp/verify
diff -rq --exclude=.git --exclude=target upstream/ /tmp/verify \
  && echo "series is faithful"                                    # expect: no output
git -C upstream worktree remove --force /tmp/verify
```

`--exclude=target` keeps build output out of the comparison; everything else —
including `upstream/Cargo.lock` — must match exactly.

## 8. Troubleshooting

| Symptom | Meaning | Fix |
|---|---|---|
| `REJECT <patch>` during `--check` or apply | upstream context drifted under that hunk | do not hand-edit the patch; run the §5 sync (step 3 conflict path) |
| `CONFLICT <patch>` in `--3way` | drifted context that git can phrase as a merge | resolve the marked files in `upstream/`, `git -C upstream add` them, re-run — already-applied patches are skipped |
| `error: <file>: does not match index` from `--3way` | misleading classic: the target tree has unstaged drift; 3way rebuilds "ours" from the index | `git -C upstream add` or reset the drift first |
| `--check` passed but `--3way` conflicts | `--check --3way` never predicts conflicts — it only asks "could I reconstruct enough to try" | trust the real apply, not the dry-run |
| tree was patched with `patch -p1` at some point | fuzz may have landed hunks in the wrong place while still compiling | `git -C upstream reset --hard HEAD`, redo with `git apply` |
| series reports 6/6 but runtime gates on the wrong platform | a fuzzed or half-applied series (e.g. `platform.rs` missing) compiles and misbehaves | reset `upstream/`, re-apply, verify §7 |
| `regenerate.sh` output looks like whole-file deletions | it ran with a tree-less HEAD (§3 consequence 3) | re-run with the fork tip checked out |
| `regenerate.sh` wants to downgrade dependencies | BASE was bumped without absorbing the base into the fork tip (§3 consequence 2) | do §5 step 3 first, then regenerate |
| upstream renamed/moved a patched file | the `TARGETS` map and headers reference dead paths | update `TARGETS` + headers, fix the fork tree, regenerate |
| patch 6 (`platform.rs`) rejects after a big upstream refactor | expected; that file is the designated fragile point | prefer re-derivation over hand-merging: resolve once in the fork merge, export via `regenerate.sh` |

## 9. Companion documents

| Document | Role |
|---|---|
| [`README.md`](README.md) | user-facing: install, usage, limitations |
| [`patches/README.md`](patches/README.md) | design rationale, patch-by-patch fragility notes, trap war stories |
| [`android/ksu/README.md`](android/ksu/README.md) | on-device module operation (`gephctl`, `service.sh`) |
| [`android/termux/README.md`](android/termux/README.md) | the unprivileged Termux install (deb, `gephsvc`, runit supervision) |
| this file | operations: keeping the series correct and syncing upstream |
