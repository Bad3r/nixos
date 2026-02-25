# Home Manager `r2-cloud`

## Scope

Document how Home Manager is wired to provide the `r2` wrapper and credential
inputs for user `vx`.

## Source of Truth

- `modules/system76/imports.nix`
- `modules/home-manager/nixos.nix`
- `modules/home/r2-secrets.nix`
- `modules/system76/r2-runtime.nix`

## Not Covered

- Producer implementation internals in
  `nix-R2-CloudFlare-Flake/modules/home-manager/*`

## Module Load Path

1. Host-level HM shared module import:
   - `inputs.r2-flake.homeManagerModules.default`
   - file: `modules/system76/imports.nix`
2. Consumer-local HM secrets module import:
   - `flake.homeManagerModules.r2Secrets`
   - loaded from `modules/home/r2-secrets.nix` via
     `modules/home-manager/nixos.nix`
3. Host-level option assignment for user `vx`:
   - `home-manager.users.${username}.programs.r2-cloud = { ... }`
   - file: `modules/system76/r2-runtime.nix`

## Active `programs.r2-cloud` Contract in This Repo

Configured values:

- `enable = true`
- `accountIdFile = "/run/secrets/r2/account-id"`
- `credentialsFile = "/run/secrets/r2/credentials.env"`
- `explorerEnvFile = "/run/secrets/r2/explorer.env"`

Operational effect:

- `r2` wrapper is in the HM user profile
- wrapper reads credentials/account ID from rendered runtime secret paths
- wrapper can source Worker share admin variables from `explorer.env`

## Relationship to HM Env Template

`modules/home/r2-secrets.nix` renders `~/.config/cloudflare/r2/env`, but current
host runtime explicitly points `programs.r2-cloud.credentialsFile` at
`/run/secrets/r2/credentials.env`.

Treat these as two valid credential surfaces:

- system path for host-managed runtime usage
- HM path for user-scoped/manual workflows

## Quick Verification

```bash
rg -n 'inputs\\.r2-flake\\.homeManagerModules\\.default' modules/system76/imports.nix
rg -n 'r2Secrets|cloudflare/r2/env' modules/home-manager/nixos.nix modules/home/r2-secrets.nix
rg -n 'home-manager\\.users\\..*programs\\.r2-cloud' modules/system76/r2-runtime.nix
```
