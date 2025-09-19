# Updating Rust Packages in This Repo

This guide summarizes the common flow for bumping Rust crates that live under `inputs/nixpkgs`.

## 1. Discover the New Release

- Identify the upstream tag you want, e.g. `rust-v0.40.0-alpha.1` for the Codex agent.
- Confirm whether the project ships multiple products; pick the tag that corresponds to the Rust workspace we package.

## 2. Prefetch the Source Tarball

- Use `nix-prefetch-url --unpack <tarball-url>` to download and unpack the new release.
- Convert the reported hash to SRI with `nix hash to-sri --type sha256 <nix-hash>`.
- For Codex the command looks like:
  ```sh
  nix-prefetch-url --unpack https://github.com/openai/codex/archive/refs/tags/rust-v0.40.0-alpha.1.tar.gz
  ```

## 3. Update `package.nix`

- Bump `version` and the `fetchFromGitHub.hash` to the new values.
- Set `cargoHash = lib.fakeSha256;` (or a dummy SRI) temporarily so Nix can compute the vendor hash on the next build.
- Adjust any tooling regex or metadata if the new tag format changes (e.g. allowing `-alpha.1`).

## 4. Recompute `cargoHash`

- Run `nix build ./inputs/nixpkgs#<package>` to trigger the vendoring derivation.
- Copy the hash from the build failure (`hash mismatch in fixed-output derivation`) and replace the dummy value.
- Re-run the build to ensure it now succeeds past the vendor stage.

## 5. Validate the Derivation

- When practical, let `nix build ./inputs/nixpkgs#<package>` finish fully.
- Enter the dev shell and run `nix develop -c pre-commit run --all-files` if broader repo checks are warranted by the change.

## 6. Document and Commit

- Summarize the update, mentioning the new version and any auxiliary changes (e.g. regex tweaks).
- Follow the Conventional Commit style, such as `chore(nixpkgs): bump codex to 0.40.0-alpha.1`.

### Troubleshooting Tips

- `cargo vendor --locked` failing usually means the upstream `Cargo.lock` needs an index refresh; rerun without `--locked` only if upstream supports it and capture the new lockfile in the source.
- If the project is split into subdirectories (Codex uses `codex-rs`), ensure `sourceRoot` still points at the correct crate workspace.
- Keep an eye on `passthru.updateScript.extraArgs`; pre-release tags might require regex changes so automation keeps working.
