# RFC-0001 Role Taxonomy Rollout (Draft)

## Overview

- Canonical Freedesktop-based role taxonomy replaces legacy bundles under `flake.nixosModules.roles`.
- `profiles.workstation` now composes System76’s workstation experience exclusively through canonical roles; hosts should import the profile instead of legacy modules.
- Phase 4 parity guard (`nix build .#checks.x86_64-linux.phase4-workstation-parity --accept-flake-config`) compares the live System76 host against `docs/RFC-0001/workstation-packages.json`.

## Required Actions for Consumers

- **Update imports:** Replace references to legacy role files with canonical paths exported by `flake.nixosModules.roles.<root>[.<subrole>]` (alias map lives in `lib/taxonomy/alias-registry.json`).
- **Adopt the profile:** Import `config.flake.nixosModules.profiles.workstation` (plus vendor extras) when targeting the canonical workstation experience.
- **Run the parity guard:** Incorporate the Phase 4 derivation into pre-merge validation to confirm manifests and roles remain in sync. When parity fails, regenerate the manifest via `nix eval .#nixosConfigurations.system76.config.environment.systemPackages --accept-flake-config --json` and follow the workflow documented in `docs/RFC-0001/implementation-notes.md`.

## Security & Tooling Notes

- Existing allowances (e.g., Ventoy insecure waiver, vendor-specific tooling) continue to flow through canonical roles such as `roles.system.prospect` and `roles.network.vendor.cloudflare`; no additional policy changes are required.
- Developer language stacks (`roles.development.{core,python,go,rust,clojure,ai}`) remain intact and are verified by the parity guard to prevent regressions.

## Guidance for Downstream Hosts

- Review `docs/configuration-architecture.md` for aggregator usage and host composition patterns.
- Consult `docs/RFC-0001/implementation-notes.md` for taxonomy wiring, alias rules, metadata validation, and manifest regeneration scripts (`taxonomy-sweep.py`, `list-role-imports.py`).
- Extend parity coverage by adding host manifests to `docs/RFC-0001/manifest-registry.json` and reusing the shared normalisation helpers in `scripts/package_utils.py`.
