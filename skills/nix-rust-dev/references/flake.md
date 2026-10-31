# Fenix + Crane setup and diagnosis

## Adapt the bundled flake

Copy `../assets/flake.nix` into a new project, or merge its pattern into the
existing flake. It assumes a committed Cargo.lock and conventional Cargo
source layout. It intentionally omits dev shells, docs/audit checks, extra
profiles, nextest, and rust-src to avoid unrelated caches and downloads.

1. Preserve project-specific native inputs, wrappers, runtime libraries,
   features, target selection, environment, and existing outputs.
2. Extend `cleanCargoSource` filtering for files used by build.rs, macros,
   include_str!/include_bytes!, tests, UI resources, and embedded integrations.
   For example, replace the `src` binding with:

   ```nix
   src = pkgs.lib.cleanSourceWith {
     src = ./.;
     filter = path: type:
       craneLib.filterCargoSources path type
       || pkgs.lib.hasInfix "/integrations/" path
       || pkgs.lib.hasSuffix "/integrations" path;
   };
   ```

   Use project-specific paths; don't include all files by default. Keep Git,
   target, result symlinks, and cache roots outside the filtered source. Check
   fixtures and workspace/path dependencies, including siblings outside the
   workspace (which may require restructuring the flake source root).
3. Use ONE `craneLib` overridden with ONE Fenix toolchain for deps, package,
   tests, Clippy, and formatting. The sample stable component set is sufficient
   for these checks. Fenix `minimal` is nightly, not minimal stable.
4. If `rust-toolchain.toml` already selects a required version, use
   `fenix.packages.${system}.fromToolchainFile` with the file and a real manifest
   `sha256`. Use `pkgs.lib.fakeSha256` once to discover the expected hash, replace
   it, and verify pure evaluation. Do not use `--impure` as a permanent fix.
5. Generate/update `flake.lock` deliberately, then commit it with Cargo.lock.
   A stable channel is reproducible at its locked Fenix revision, not permanently
   pinned to the same Rust release after a lock update. Avoid routine updates
   while iterating: compiler and nixpkgs changes invalidate dependency caches.
6. Build the dependency root, package, and checks. Follow the skill's reuse
   verification procedure before claiming the setup works.

## What Crane does (and does not do)

`buildDepsOnly` substitutes dummy crate sources so ordinary implementation
edits need not change the dependency derivation. `buildPackage`, `cargoTest`,
and `cargoClippy` receive that derivation through `cargoArtifacts`. Crane handles
artifact transfer/fingerprints; do not implement ad-hoc `cp target` + `touch`
cache repair or override the dummy source with real application sources.

Dependency artifacts can be reused across builds with matching inputs; Nix
still runs each changed application derivation in a new sandbox. It is not a
mutable Cargo target directory. Build-time artifacts are typically much larger
than the final binary. Crane's artifact handling is preferable to copying a
complete target tree into every application output.

`buildDepsOnly` normally builds check metadata, normal dependencies, and test
artifacts. Do not set `doCheck = false` in shared arguments just because tests
are separate: that can remove dev-dependency prebuilding. Disable it only on
the final `buildPackage`. Tests and Clippy may still need additional work,
especially for different features/targets. More cache variants cost more disk.

## If dependencies rebuild after a source edit

Compare `cargoArtifacts.drvPath` before and after. If it changed, inspect:

- Cargo manifests/lock, workspace layout, .cargo config, build scripts, and
  other files retained in the dummy source;
- toolchain, nixpkgs, native inputs, Cargo profile, target triple, feature flags,
  RUSTFLAGS, hooks, and environment;
- interpolations like `${src}` in dependency hooks/environment, which can tie
  dependency derivation inputs to real implementation content;
- whether files included for assets unnecessarily enter dependency preparation.

If the derivation is identical but Cargo recompiles dependencies, inspect `-L`
logs (temporarily add Cargo `-vv` if necessary) for fingerprint mismatches.
Confirm consumers really receive `cargoArtifacts`, the same toolchain/profile/
features/flags/native inputs, and that no custom hook discards the cache.
Different profiles, tests, Clippy, proc macros, build scripts, and cross targets
can legitimately need different artifacts. Don't claim every compilation is a
cache failure or fix it by forcing stale fingerprints.

If Nix rebuilds an identical derivation after GC, retain the explicit artifact
root. `--no-link` and runtime binary roots alone do not preserve every build-time
dependency. Don't disable GC globally to fix a project cache.

## Upstream references

- Crane quick start: https://crane.dev/examples/quick-start.html
- Crane API: https://crane.dev/API.html
- Dependency preparation implementation: https://github.com/ipetkov/crane/blob/master/lib/buildDepsOnly.nix
- Fenix toolchains and Crane integration: https://github.com/nix-community/fenix#readme
