# Updating the `codex` Package

This guide describes the exact steps for bumping `packages/codex/default.nix` to a new upstream commit of the Codex repository. Follow it whenever the CLI needs to track a different revision.

## 1. Pick the Target Commit

- Identify the Codex Git commit you want to ship (for example `b8195a17e572a149d89ebea3a080a456787e3432`).
- Double-check that the commit still contains the `codex-rs` workspace; the derivation expects that path.

## 2. Prefetch the Source

Use `nix-prefetch-github` so you get both the source hash and the SRI in one shot:

```sh
nix shell nixpkgs#nix-prefetch-github -c \
  nix-prefetch-github openai codex --rev <commit>
```

Record the reported `hash` value—you will plug it into the derivation.

## 3. Update `packages/codex/default.nix`

1. Set `rev` to the new commit.
2. Replace the `hash` inside `fetchFromGitHub { ... }` with the SRI you just obtained.
3. Leave `version = "0.0.0";` untouched because upstream still reports `codex-cli 0.0.0`.
4. Temporarily set `cargoHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";` to force Nix to emit the vendor hash on the next build.
5. If the changelog URL includes the commit, ensure it lines up with the new `rev`.

## 4. Recompute `cargoHash`

Let Nix report the correct vendor hash—this is the authoritative value. After setting `cargoHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";`, trigger a build:

```sh
nix build .#packages.x86_64-linux.codex
```

The build will fail with a fixed-output derivation mismatch and print both the placeholder and the expected SRI. Copy the `got:` value from that error message into `cargoHash` in `packages/codex/default.nix`. **Do not** attempt to recalculate the vendor hash via `cargo vendor`/`nix hash path`; those workflows can drift and waste time.

If you already hit the hash mismatch and updated `cargoHash`, stop here—there is no need to rebuild just to see it succeed.

## 5. Defer Final Verification

Do **not** perform a full verification build once the hashes line up. Leave the final `nix build`/`nix flake check` runs to the requesting maintainer so they can execute them in their own environment.

## 6. Tips to Minimize Future Hash Runs

- **Capture the mismatch once:** As soon as Nix prints the `got:` hash, stash it in your notes or PR description so you never need to re-run the placeholder build.
- **Keep the Cargo cache warm:** Preserve `~/.config/cargo/registry` and `~/.config/cargo/git` between updates so the single `nix build` needed for the mismatch pulls dependencies faster.
- **Add binary caches when possible:** Extra Nix cache endpoints (e.g. corporate or community mirrors) reduce time spent downloading toolchains during that initial build.
- **Archive previous hashes:** Tracking past `got:` values makes it easy to spot when the dependency graph genuinely shifted versus when only the source revision changed.

Following these steps keeps Codex pinned to the desired revision while minimizing wasted time on repeated hash calculations.
