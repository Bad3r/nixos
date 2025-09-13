Vendored inputs workflow (git+file)

This repo vendors key flake inputs as Git submodules under `inputs/` and points
flake inputs at them via `git+file:./inputs/<name>`. This removes noisy
`cannot fetch input 'path:…'` messages and makes locks record explicit commits.

Workflow

- Edit the submodule as needed, e.g. `inputs/nixpkgs/pkgs/...`.
- Commit changes inside the submodule (`git -C inputs/nixpkgs commit ...`).
- Update the superproject to point to the submodule HEAD (`git add inputs/nixpkgs`).
- Optionally update `flake.lock` to reflect the new commits:
  - `nix flake lock --update-input nixpkgs --update-input home-manager --update-input stylix`
- Push. The pre-push hook pushes changed submodule heads to your origin and
  hard-fails if a squashed upstream provenance check fails.

Notes

- Evaluation still uses vendored nixpkgs via the existing
  `nixpkgs.flake.source = rootPath + "/inputs/nixpkgs"` override.
- Uncommitted submodule edits are discouraged; commit them for reproducibility
  (dirty trees will warn and are not pinned).
