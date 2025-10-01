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

The easiest way to get the vendor hash is to run `cargo vendor` yourself so you avoid multiple full Nix builds:

1. Evaluate the package once to locate the fetched source:
   ```sh
   nix eval --raw .#packages.x86_64-linux.codex.src
   ```
2. Copy the `codex-rs` workspace from that store path to a writable directory (`mktemp -d` works well) and `chmod` it if needed.
3. Enter the repo dev shell and vendor the dependencies:
   ```sh
   nix develop -c cargo vendor --locked --versioned-dirs
   ```
4. Compute the SRI for the generated `vendor` tree:
   ```sh
   nix hash path vendor
   ```
5. Paste the result back into `cargoHash` in `packages/codex/default.nix`.

Make sure whatever shell or CI runner you are using allows at least a 30 minute timeout (for example `timeout_ms = 1_800_000` in the Codex CLI). Large dependency graphs routinely need the full window, so try to capture every change you need from a single vendoring attempt.

## 5. (Optional) Validate the Derivation

When time allows, run:

```sh
nix build .#packages.x86_64-linux.codex
```

That ensures the vendored tree matches what Nix expects and catches any build regressions.

## 6. Tips to Minimize Future Hash Runs

- **Reuse `cargo vendor` state:** Run the vendoring step manually in a dev shell as shown above; it skips downstream build phases and finishes as soon as the crates are copied.
- **Keep the Cargo cache warm:** Preserve `~/.config/cargo/registry` and `~/.config/cargo/git` between updates so the vendor run reuses previously downloaded crates instead of fetching gigabytes again.
- **Add binary caches when possible:** Extra Nix cache endpoints (e.g. corporate or community mirrors) reduce time spent pulling toolchains during validation builds, letting you focus on vendoring only once.
- **Archive previous vendor trees:** Stash the `vendor` directory and its hash for each Codex update. If the dependency graph barely changes, diffing against the archived tree helps confirm whether a new vendoring pass is necessary before spending another long run.

Following these steps keeps Codex pinned to the desired revision while minimizing wasted time on repeated hash calculations.
