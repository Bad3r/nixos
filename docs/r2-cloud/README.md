# R2 Cloud Integration

This directory documents how `/home/vx/nixos` consumes
`Bad3r/nix-R2-CloudFlare-Flake` for host `system76` and user `vx`.

## Scope

- Consumer-side wiring in this repository:
  - flake input registration
  - NixOS/Home Manager module import chain
  - `secrets/r2.yaml` to runtime file rendering
  - host runtime configuration (`services.r2-sync`, `services.r2-restic`,
    `programs.git-annex-r2`, `programs.r2-cloud`)
- Operator validation and drift checks
- Failure-mode troubleshooting for this integration

## Source of Truth

- `flake.nix` (`inputs.r2-flake`)
- `modules/system76/imports.nix` (producer module imports)
- `modules/security/r2-cloud-secrets.nix` (system secrets/templates)
- `modules/home/r2-secrets.nix` (HM secrets/template)
- `modules/system76/r2-runtime.nix` (runtime consumers)
- `modules/security/sops-policy.nix` (SOPS creation rule for `secrets/r2.yaml`)

## Not Covered

- `services.duplicati-r2` and `secrets/duplicati-r2.yaml`
- Cloudflare Worker deployment workflows owned by the producer repo
- General SOPS onboarding (see `../sops/README.md`)

## Reading Order

| Document                         | Purpose                                                          |
| -------------------------------- | ---------------------------------------------------------------- |
| `input-and-module-wiring.md`     | Exact integration path from `inputs.r2-flake` to host/HM imports |
| `secrets-and-rendered-files.md`  | `secrets/r2.yaml` key mapping and rendered file contract         |
| `system76-runtime.md`            | Runtime service and mount layout currently enabled on this host  |
| `home-manager-r2-cloud.md`       | HM-side wrapper, secret template, and module loading behavior    |
| `validation-and-drift-checks.md` | Commands to prove integration is still wired correctly           |
| `troubleshooting.md`             | Fast diagnosis for common breakages                              |

## Upstream Producer Docs

- Repository:
  <https://github.com/Bad3r/nix-R2-CloudFlare-Flake>
- Option reference index:
  <https://github.com/Bad3r/nix-R2-CloudFlare-Flake/blob/main/docs/reference/index.md>
- Quickstart:
  <https://github.com/Bad3r/nix-R2-CloudFlare-Flake/blob/main/docs/quickstart.md>
