# CI Evaluation Without the Submodule

GitHub runners cannot read the private `Bad3r/secrets` repository, and `self.submodules = true` makes every git-based self fetch pull it.
CI therefore evaluates through the path fetcher:

```sh
nix flake check --accept-flake-config --no-build "path:."
```

`path:` copies what is on disk rather than the tracked tree, so it never consults the gitlink and never needs the submodule fetched.
Secret files are absent on a CI runner because the submodule is not checked out there, not because the fetcher skips it.
The per-file `builtins.pathExists` guards then evaluate the secretless configuration and emit `... is missing; skipping ...` warnings instead of failing, which `abort-on-warn = false` keeps non-fatal.
`--no-build` is required because the flake exposes both host toplevels as checks, and building them exceeds runner disk.

That trades evaluation fidelity for a credential-free CI: sops-gated modules are skipped, and local rebuilds remain the full-fidelity gate.
CI holds no read credential for `Bad3r/secrets`.

## Local `path:` copies

Locally the same command behaves differently, because the submodule working tree is present.
`path:` copies `secrets/` whole into the world-readable store, including the `decrypted_*` and `*.dec.*` outputs that the submodule's own `.gitignore` hides and that the editing workflows produce.
The superproject sweep stops at the gitlink, so run both sweeps from the repository root before any `path:` command:

```sh
git status --porcelain --ignored=matching
git submodule foreach --recursive 'git status --porcelain --ignored=matching'
```
