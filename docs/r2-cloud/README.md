# R2 Cloud Integration

This directory documents how `/home/vx/nixos` consumes
`Bad3r/nix-R2-CloudFlare-Flake` for user `vx`. Each host wires the integration
through the shared builder `flake.lib.nixos.r2.mkHostR2Module` with a per-host
policy. The current `system76` and `tpnix` policies enable the producer runtime;
the builder still gates imports and runtime assignments on each host's readiness
flag and the encrypted `secrets/r2.yaml` payload.

## Scope

- Consumer-side wiring in this repository:
  - flake input registration
  - NixOS/Home Manager module import chain and per-host enable policy
  - `secrets/r2.yaml` to runtime file rendering
  - host runtime configuration (`services.r2-sync`, `services.r2-restic`,
    `programs.git-annex-r2`, `programs.r2-cloud`)
- Operator validation and drift checks
- Failure-mode troubleshooting for this integration

## Source of Truth

- `flake.nix` (`inputs.r2-flake`)
- `modules/lib/r2-runtime.nix` (shared builder: gated producer module imports
  and runtime consumers)
- per-host `modules/<host>/r2-runtime.nix` (policy passed to the builder)
- `modules/hosts/common/imports.nix` (`security.r2CloudSecrets.enable` and
  `home.r2Secrets.enable` defaults)
- `modules/security/r2-cloud-secrets.nix` (system secrets/templates)
- `modules/home/r2-secrets.nix` (HM secrets/template)
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
| `system76-runtime.md`            | Host policy and the service/mount layout applied when enabled    |
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
