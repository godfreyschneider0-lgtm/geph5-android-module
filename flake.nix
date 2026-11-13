{
  description = "geph5 fork — Android module + reproducible Nix build of the same patched tree";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = lib.genAttrs systems;

      # The same series that drives the Android build drives this one: sorted
      # by filename, applied in order by the package derivation.
      patchSeries =
        let
          names = builtins.attrNames (builtins.readDir ./patches);
          series = builtins.filter (lib.strings.hasSuffix ".patch") names;
        in
        map (name: ./patches/${name}) (lib.naturalSort series);

      # Workspace version of the fork tree at the repo root; patches/BASE pins
      # the upstream commit this version was written against.
      version = (builtins.fromTOML (builtins.readFile ./Cargo.toml)).workspace.package.version;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          geph5 = pkgs.callPackage ./nix/package.nix {
            inherit patchSeries version;
            upstreamRev = lib.strings.trim (builtins.readFile ./patches/BASE);
            # sha256 of the unpacked tarball at upstreamRev (codeload URL, see
            # nix/package.nix); update it when patches/BASE moves.
            upstreamHash = "sha256-AFkf2RgH4xuGL1fEJbEzRiQBxciCQYmY4igY3xyYXlg=";
          };
          default = self.packages.${system}.geph5;
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          # Hacking on the fork tree itself (cargo check / clippy / test).
          default = pkgs.mkShell {
            packages = with pkgs; [
              cargo
              rustc
              rust-analyzer
              clippy
              pkg-config
              openssl
              sqlite
            ];
          };
        }
      );
    };
}
