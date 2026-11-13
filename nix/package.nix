{
  lib,
  stdenv,
  rustPlatform,
  fetchzip,
  pkg-config,

  # NixOS has no FHS; the engine shells out to these helpers at runtime, so
  # they are substituted to absolute store paths (same treatment as the
  # nixpkgs geph5 package gives its copy).
  iproute2,
  nftables,
  shadow,
  systemd,

  openssl,
  sqlite,

  git, # postPatch applies the series with `git apply`, like apply-patches.sh

  # from the flake (this repository)
  patchSeries,
  upstreamRev,
  upstreamHash,
  version,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "geph5";
  inherit version;

  # Build input is the pristine upstream tree at the commit recorded in
  # patches/BASE — never the fork copy at the repo root, which is a readable
  # reference only. Every build re-proves the series still applies.
  src = fetchzip {
    # codeload URL instead of fetchFromGitHub: same pinned tarball, but the
    # URL keeps working on hosts where github.com itself is unreachable. The
    # URL carries no .tar.gz suffix, so the unpacker is told explicitly.
    url = "https://codeload.github.com/geph-official/geph5/tar.gz/${upstreamRev}";
    extension = "tar.gz";
    hash = upstreamHash;
  };

  # The fork's lock, which already carries the dependency delta the series
  # introduces (libc on geph5-app / geph5-misc-rpc for the android cfg arms).
  cargoLock.lockFile = ../Cargo.lock;

  postPatch =
    # 1. The series, exactly as apply-patches.sh applies it for the Android
    #    build: git apply (never GNU patch with fuzz), strictly in filename
    #    order, so a drifted patch fails the build loudly instead of shipping
    #    silently-wrong code.
    lib.concatMapStringsSep "\n" (p: ''
      echo "nix build: applying ${baseNameOf (toString p)}"
      git apply ${p}
    '') patchSeries
    + lib.optionalString stdenv.hostPlatform.isLinux ''
      # 2. NixOS-specific: point the spawned helpers at the store.
      substituteInPlace binaries/geph5-app/src/platform.rs \
        --replace-fail 'run_status("systemctl"' 'run_status("${lib.getExe' systemd "systemctl"}"' \
        --replace-fail '"useradd",' '"${lib.getExe' shadow "useradd"}",' \
        --replace-fail '"/usr/sbin/nologin"' '"${shadow}/sbin/nologin"'

      substituteInPlace binaries/geph5-app/src/vpn/linux.rs \
        --replace-fail 'Command::new("nft")' 'Command::new("${lib.getExe nftables}")' \
        --replace-fail 'run("ip"' 'run("${lib.getExe' iproute2 "ip"}"' \
        --replace-fail '        "ip",' '        "${lib.getExe' iproute2 "ip"}",'
    '';

  nativeBuildInputs = [
    pkg-config
    git
  ];

  buildInputs = [
    openssl
    sqlite
  ];

  env = {
    # Link against nixpkgs openssl/sqlite instead of vendored copies.
    OPENSSL_NO_VENDOR = "1";
    LIBSQLITE3_SYS_USE_PKG_CONFIG = "1";
  };

  # Same package selection as android/build-module.sh: the app binary
  # (`geph5`, manager + CLI) and the client engine. The broker/exit/bridge
  # members are never compiled.
  cargoBuildFlags = [
    "-p"
    "geph5-app"
    "-p"
    "geph5-client"
  ];
  cargoInstallFlags = finalAttrs.cargoBuildFlags;

  # The suites need a live broker or a peer (and some never finish); the
  # Android build skips them for the same reason.
  doCheck = false;

  # cargo install may drop the geph5-client cdylib/staticlib outputs here;
  # this package ships exactly two binaries.
  postInstall = ''
    rm -rf "$out/lib"
  '';

  meta = {
    description = "Geph5 anti-censorship client, built from the patch series of geph5-android-module";
    homepage = "https://github.com/godfreyschneider0-lgtm/geph5-android-module";
    license = lib.licenses.mpl20;
    mainProgram = "geph5";
    platforms = lib.platforms.linux;
  };
})
