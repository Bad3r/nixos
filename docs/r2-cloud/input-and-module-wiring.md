# Input and Module Wiring

## Scope

Document the exact code path that wires `nix-R2-CloudFlare-Flake` into this
repository.

## Source of Truth

- `flake.nix`
- `modules/system76/imports.nix`
- `modules/home-manager/nixos.nix`

## Not Covered

- Runtime unit behavior and mount layout (see `system76-runtime.md`)
- Secret key mapping details (see `secrets-and-rendered-files.md`)

## Wiring Path

1. Producer flake input is registered:
   - `inputs.r2-flake.url = "github:Bad3r/nix-R2-CloudFlare-Flake?ref=main";`
   - File: `flake.nix`
2. NixOS module surface is imported for `system76`:
   - `inputs.r2-flake.nixosModules.default`
   - File: `modules/system76/imports.nix`
3. Home Manager module surface is appended for `system76`:
   - `inputs.r2-flake.homeManagerModules.default`
   - File: `modules/system76/imports.nix`
4. Repo-local HM secrets module is also loaded globally:
   - `flake.homeManagerModules.r2Secrets` from `modules/home/r2-secrets.nix`
   - wired by `modules/home-manager/nixos.nix`

## Why Both HM Module Paths Exist

- `inputs.r2-flake.homeManagerModules.default` provides the producer wrapper
  and option surfaces (`programs.r2-cloud`, credentials behavior, rclone
  integration).
- `flake.homeManagerModules.r2Secrets` is consumer-local and only handles this
  repo's SOPS materialization to `~/.config/cloudflare/r2/env`.

These two paths are complementary: producer logic + consumer secret plumbing.

## Quick Verification

```bash
rg -n 'r2-flake\\.url' flake.nix
rg -n 'inputs\\.r2-flake\\.(nixosModules|homeManagerModules)\\.default' modules/system76/imports.nix
rg -n 'r2Secrets' modules/home-manager/nixos.nix modules/home/r2-secrets.nix
```

Expected result:

- all three commands return at least one match
- no local host path override is required for normal operation (use Nix input
  override only for temporary producer-development testing)
