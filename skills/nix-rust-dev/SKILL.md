---
name: nix-rust-dev
description: Build, test, lint, and iterate on Rust projects on NixOS using Fenix and Crane with reusable dependency artifacts. Use for Rust flakes, Nix Rust build setup, slow dependency rebuilds, or target/ and Nix store disk growth.
compatibility: Requires Nix with nix-command and flakes enabled. Rust compilation runs through project flake outputs.
---

# Storage-conscious Rust development on NixOS

Prefer sandboxed Nix builds with Crane's dependency/application split and a
Fenix toolchain pinned by `flake.lock`. Do not promise zero disk growth: each
source revision can produce a new store output, and application compilation is
not incremental across Nix builds. The saving is reusing dependency artifacts
and keeping Cargo's build directory out of the checkout.

## Inspect before building

Read `flake.nix`, `Cargo.toml`, `.cargo/config.toml` and `rust-toolchain.toml`
when present. Inspect workspace members, features, native libraries, build
scripts, assets, `include_str!`/`include_bytes!`, and existing outputs. Preserve
working project conventions; do not replace a flake just to follow this skill.

If setup or migration is needed, read `references/flake.md` and adapt
`assets/flake.nix` (paths are relative to this skill directory). Prefer Fenix
**stable**, not `minimal`/`default` (those are nightly). Respect an existing
MSRV or nightly requirement. Do not update lock files/toolchains incidentally.
Do not require nixcenter scaffolding for an existing Rust project.

Check `git status --short` and `du -sh target .git .nixcenter 2>/dev/null`.
Prefer `.#` in a Git repository: modified tracked files are included, but new
untracked files are not. Identify missing build inputs; ask before staging
user files, never stage everything automatically. For untracked inputs, use
`path:.#` only after checking checkout size and contents, or make a small
external source snapshot excluding `.git`, `target`, result symlinks, caches,
and secrets. Filtering `src` inside the flake does NOT prevent Nix from first
copying the entire `path:.` flake to the store.

## Build loop

Use actual output names from the project; these examples match the bundled
reference flake. `cargoArtifacts` and the named checks are not universal.

```sh
# Keep ONE current dependency-artifact root, before starting source iteration.
mkdir -p .nixcenter
nix build .#cargoArtifacts --out-link .nixcenter/cargo-artifacts -L

# Source edits: no checkout target/, no persistent application output root.
nix build .# --no-link -L

# Targeted verification, then the full defined check suite before finishing.
nix build .#checks.x86_64-linux.tests --no-link -L
nix build .#checks.x86_64-linux.clippy --no-link -L
nix flake check -L

# Optional final binary: one replaceable root, not result-<revision> roots.
nix build .# -L
./result/bin/<binary> --help
```

Replace `x86_64-linux` with the project system. Check what the flake actually
runs: `checks.default = package` does not necessarily run tests or Clippy.
Run headless `--help`/`--version` only when supported; do not launch an
interactive TUI/GUI in the agent shell. Report commands and unrun checks.

Use `nix fmt` only if a formatter is defined (it usually formats Nix, not Rust).
For Rust formatting, use the pinned toolchain, e.g.
`nix shell .#rustToolchain -c cargo fmt --all`. Formatting does not compile.

Default to Nix outputs for compilation, tests, and linting. Do not silently run
`cargo build/run/test/check/clippy/install/watch` or enter `nix develop` to
compile: that creates a separate artifact cache. Cargo metadata/tree/version
and fmt are fine. If the user requests an interactive incremental Cargo workflow,
explain the disk/performance tradeoff and use one stable external
`CARGO_TARGET_DIR`, not a fresh cache per shell/revision. A skill is guidance,
not a tool-enforcement plugin; no OpenCode `nix_rust_*` tools are required.

## Prove reuse rather than assume it

Before and after an ordinary Rust source edit, evaluate:

```sh
nix eval --raw .#cargoArtifacts.drvPath
```

The dependency derivation path should remain identical. Then build the app
with `-L`: dependencies should be reused and the changed crate rebuilt. Verify
changed behavior or tests too. Don't mistake an old binary for a cache hit.
For an isolated scratch project, change a dependency/feature and confirm that
the dependency derivation DOES change. Never edit user dependencies just for
this test. See the reference for cache invalidation diagnosis.

## Disk policy

- `--no-link` makes new outputs collectable; it does not delete them. Store
  growth continues until GC runs. Builds still need temporary sandbox space.
- Root only the current `cargoArtifacts` if reuse across GC matters. Rebuilding
  that link replaces the old root; don't keep one per revision. Add
  `/.nixcenter/`, `/target/`, `/result`, `/result-*` to project ignores as needed.
- A package's runtime closure need not retain its build-time artifact cache.
  Keep the explicit dependency root. Rooting artifacts also retains their
  referenced store closure; measure instead of guessing.
- Inspect `nix path-info -Sh .#cargoArtifacts`, `df -h /nix/store`, and
  `nix-store --gc --print-roots` when diagnosing space. Do not delete someone
  else's roots, old target directories, system generations, or lock files.
- Never run GC or `nix-collect-garbage -d` automatically. With explicit user
  permission, `nix store gc --dry-run` previews eligible paths and
  `nix store gc` collects them machine-wide. Even this can evict unrelated
  unrooted caches; `--delete-older-than` also removes generations and is NOT
  a project-local safe cleanup command.
- Never change global substituters, trusted keys, sandbox settings, or
  automatic GC policy without permission.
