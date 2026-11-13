# The Nix build

The Nix counterpart of `android/build-module.sh`: same source, same patch
series, different packaging target (Linux hosts instead of Android).

## What it builds

`geph5` (the manager + CLI binary from `geph5-app`) and `geph5-client`, from
the **pristine upstream geph5 tree pinned by `patches/BASE`** with the
`patches/` series applied by the derivation itself — never from the fork copy
at the repo root, which is a readable reference only. Every Nix build
therefore re-proves that the series still applies, exactly like the Android
build does.

Differences from upstream's own binaries:

- the helpers the engine spawns (`systemctl`, `useradd`, `nologin`, `ip`,
  `nft`) are substituted to absolute nix store paths — no FHS assumptions;
- openssl and sqlite link against nixpkgs' copies (`OPENSSL_NO_VENDOR=1`,
  `LIBSQLITE3_SYS_USE_PKG_CONFIG=1`) instead of vendored builds;
- only `geph5-app` and `geph5-client` are compiled (`-p` selection, same as
  the Android build); broker/exit/bridge are not.

## Usage

```bash
nix build .#geph5                       # into ./result
nix run .#geph5 -- --help
nix profile install .#geph5
./nix/build-nix.sh                      # one-shot: build + tarball into nix/dist/
```

The tarball from `build-nix.sh` is for non-Nix Linux machines of a compatible
distro generation; its binaries link the build generation's glibc, so on
NixOS always prefer the flake outputs.

The manager spawns `geph5-client` from `PATH` (or `$GEPH_CLIENT_BIN`). Both
binaries live in the same `bin/` of this package, so having the package on
`PATH` is enough; for a system service, set `GEPH_CLIENT_BIN` explicitly.

## Updating

Nothing version-specific lives in `nix/`. After syncing the series to a new
`patches/BASE` (see `../MAINTENANCE.md`), the first `nix build` fails with a
hash mismatch for the new upstream tarball — paste the `got: sha256-…` into
`upstreamHash` in `../flake.nix` and rebuild. The version is read from the
workspace `Cargo.toml`, and the Cargo.lock comes from the repo root.
