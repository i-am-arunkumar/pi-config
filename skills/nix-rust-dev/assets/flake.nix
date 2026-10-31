{
  description = "Rust application: pinned Fenix toolchain and shared Crane artifacts";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    crane.url = "github:ipetkov/crane";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, crane, fenix, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      perSystem = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          toolchain = fenix.packages.${system}.stable.withComponents [
            "cargo" "rustc" "clippy" "rustfmt"
          ];
          craneLib = (crane.mkLib pkgs).overrideToolchain toolchain;
          # Extend this filter for assets, fixtures, include_str!, etc.
          # For nixcenter itself, the embedded integrations/ files are required.
          src = craneLib.cleanCargoSource ./.;
          commonArgs = {
            inherit src;
            strictDeps = true;
            # Keep profile, features, target, flags, and native inputs aligned.
            cargoExtraArgs = "--locked";
            CARGO_PROFILE = "release";
            CARGO_INCREMENTAL = "0";
            nativeBuildInputs = [ ]; # e.g. pkgs.pkg-config
            buildInputs = [ ]; # e.g. pkgs.openssl
          };
          # Leave doCheck enabled here: Crane prebuilds dev/test dependencies
          # and check metadata as well as normal compilation artifacts.
          cargoArtifacts = craneLib.buildDepsOnly commonArgs;
          withArtifacts = commonArgs // { inherit cargoArtifacts; };
          package = craneLib.buildPackage (withArtifacts // {
            doCheck = false; # Tests are a separate check, not run twice.
          });
        in {
          packages = {
            default = package;
            inherit cargoArtifacts;
            rustToolchain = toolchain;
          };
          checks = {
            inherit package;
            tests = craneLib.cargoTest withArtifacts;
            clippy = craneLib.cargoClippy (withArtifacts // {
              cargoClippyExtraArgs = "--all-targets -- --deny warnings";
            });
            fmt = craneLib.cargoFmt { inherit src; };
          };
          formatter = pkgs.nixfmt;
        });
    in {
      packages = forAllSystems (system: perSystem.${system}.packages);
      checks = forAllSystems (system: perSystem.${system}.checks);
      formatter = forAllSystems (system: perSystem.${system}.formatter);
    };
}
