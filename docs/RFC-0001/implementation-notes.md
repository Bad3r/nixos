# RFC-0001 Implementation Notes

## Category Extraction

Use the AppStream metadata bundled with nixpkgs packages to capture Freedesktop categories:

```bash
pkg=$(nix build --print-out-paths nixpkgs#gnome-disk-utility)
grep '^Categories=' "$pkg"/share/applications/*.desktop

# Optionally inspect the AppStream XML directly
nix shell nixpkgs#appstream-glib -c \
  appstream-util info "$pkg"/share/metainfo/*.xml | rg '^Categories'
```

Replace `gnome-disk-utility` with any package name; the pattern works the same for other roles. The workstation manifest `docs/RFC-0001/workstation-packages.json` is generated with this approach via `nix eval ... --json`.

The taxonomy helper library lives under `lib/taxonomy`. It bundles a generated `freedesktop-categories.json` snapshot (collected from the local `nixpkgs` mirror via `rg 'Categories='`) plus a curated `metadata-overrides.json` for packages that ship no `.desktop` file (e.g., CLI-only utilities or custom wallpapers). Phase 0’s metadata lint checks role metadata against those two files so local overrides stay auditable.

### Manifest Registry & Override Sweep

- `docs/RFC-0001/manifest-registry.json` records every package manifest that participates in the override sweep. Currently it only lists `docs/RFC-0001/workstation-packages.json`; add future hosts/profiles here so they are swept automatically.
- Run `./scripts/taxonomy-sweep.py` to regenerate `lib/taxonomy/metadata-overrides.json`. The script:
  - Loads manifests from the registry (or `--manifest path.json` flags).
  - Skips packages that expose `.desktop` files in the local `nixpkgs`, `home-manager`, or `nixos_docs_md` mirrors.
  - Applies curated overrides for special cases (`system76-wallpapers`, `prettier`, etc.).
  - Uses asset-aware heuristics to mark icon themes, fonts, locales, and other data packages with `secondaryTags = ["asset"]` while keeping CLI tooling tagged with `secondaryTags = ["cli"]`.
  - Emits a review queue at `build/taxonomy/metadata-overrides-review.json` for manual inspection of asset-heavy packages after each run.
- After reviewing flagged entries, commit both the updated overrides and the review artefact (or delete the review file once emptied) so the history captures the triage outcome.

### Role Import Inventory

- Run `scripts/list-role-imports.py` to list every `flake.nixosModules.roles.*` export and the app modules it imports. Use `--format json` for machine-readable output when checking for duplicate payloads or validating bundle coverage.
- The report lists non-app imports by attribute path (for example `lang.python`, `roles.xserver`). Local helper modules fall back to their defining file so the audit trail stays readable without a full NixOS evaluation context.
- The reporter accepts `--repo /path/to/root` when invoked from CI or temporary directories; CI uses this flag so the new `phase0-role-imports` check surfaces regressions automatically.

### Phase 4 Parity Validation

- `scripts/package_utils.py` centralises package-name normalisation (removing store hashes and version suffixes) for manifests, role inventories, and live host evaluations. Phase 0’s host-package guard now shells out to this helper instead of maintaining ad-hoc regular expressions.
- `nix build .#checks.x86_64-linux.phase4-workstation-parity --accept-flake-config` runs `checks/phase4/workstation-parity.py`, which compares `docs/RFC-0001/workstation-packages.json` against `nixosConfigurations.system76.config.environment.systemPackages`. The script prints missing and unexpected package lists when parity fails and exits non-zero so CI blocks the regression.
- When the System76 manifest changes, regenerate `docs/RFC-0001/workstation-packages.json` via `nix eval` and rerun the parity check before committing. If the check fails, reconcile the manifest or role definitions until both hosts and manifest agree.

## Vendor Bundle Template

```nix
# modules/roles/system/vendor/system76/default.nix
{ lib, inputs, ... }:
{
  flake.nixosModules.roles.system.vendor.system76 = {
    metadata = {
      canonicalAppStreamId = "System";
      categories = [ "System" "Settings" ];
      auxiliaryCategories = [ "Utility" ];
      secondaryTags = [ "hardware-integration" "vendor-system76" ];
    };

    imports = [
      inputs.self.nixosModules.apps.system76-firmware
      inputs.self.nixosModules.apps.system76-keyboard-configurator
      inputs.self.nixosModules.apps.system76-wallpapers
    ];
  };
}
```

Adapt the import list for other vendors; keep metadata in sync with the taxonomy helper library.

## Alias Registration

- `roles.sys` → `roles.system`
- `roles.base` → `roles.system.base`
- `roles.xserver` → `roles.system.display.x11`
- `roles.security` → `roles.system.security`
- `roles.files` → `roles.system.storage`
- `roles.cli` → `roles.utility.cli`
- `roles.media` → `roles.audio-video.media`
- `roles.net` → `roles.network.tools`
- `roles.cloudflare` → `roles.network.vendor.cloudflare`
- `roles.file-sharing` → `roles.network.sharing`
- `roles.dev` → `roles.development.core`
- `roles.dev.python`, `roles.dev.py` → `roles.development.python`
- `roles.dev.go` → `roles.development.go`
- `roles.dev.rust` → `roles.development.rust`
- `roles.dev.clj` → `roles.development.clojure`
- `roles.ai-agents` → `roles.development.ai`
- `roles.gaming` → `roles.game.launchers`
- `roles.productivity` → `roles.office.productivity`

Extend the mapping for any additional convenience aliases required by future language bundles. Because aliases live here instead of the module names, renaming a canonical role (e.g., `roles.development` → `roles.devel`) only requires updating this map so that shorthands such as `roles.dev.py` continue to resolve.

## Workstation Profile Composition

`profiles.workstation` now imports the canonical taxonomy directly:

- `roles.system.base`, `roles.system.display.x11`, `roles.system.storage`, `roles.system.security`
- `roles.system.nixos`, `roles.system.virtualization`
- `roles.utility.cli`, `roles.utility.monitoring`, `roles.utility.archive`
- `roles.development.core` and the language bundles (`roles.development.python`, `.go`, `.rust`, `.clojure`, `.ai`)
- `roles.audio-video.media`
- `roles.network.tools`, `roles.network.remote-access`, `roles.network.sharing`, `roles.network.vendor.cloudflare`
- `roles.office.productivity`
- `roles.game.launchers`

### Phase 3 Parity Snapshot (2025-10-14)

- Baseline manifest captured at `docs/RFC-0001/workstation-packages-phase2.json` (380 packages).
- Current manifest `docs/RFC-0001/workstation-packages.json` (376 packages as of 2025-10-15) reflects the taxonomy-backed profile.
- Added packages: `avahi`, `getconf-glibc`, `getent-glibc`, `mpv-with-scripts`, `nano`, `nix-index-with-full-db`, `nvidia-x11`, `openresolv`, `sudo`, `wpa_supplicant`.
- Removed packages span developer tooling (`neovim`, `git`, `cmake`, `rust-analyzer`, `ShellCheck`), key desktop integrations (`steam`, `wireguard-tools`, `NetworkManager-openvpn`), and cloud/network utilities (for example `cloudflared`, `fail2ban`). Firefox, Discord, and Element remain in the manifest; see the diff for the full removal list and flag intentional drops before closing Phase 3.
- TODO: wire the future Phase 4 parity derivation (`.#checks.x86_64-linux.phase4-workstation-parity`) once implemented so the manifests stay in lock-step.

Legacy aliases (for example `roles.media`, `roles.net`, `roles.cloudflare`, `roles.file-sharing`) remain in
`lib/taxonomy/alias-registry.json` but no longer have dedicated shim modules—the workstation profile resolves the
canonical roles directly.

Host- or vendor-specific packages (e.g., System76 utilities, USBGuard policies) remain in the host configuration or
dedicated vendor roles. For example, `configurations.nixos.system76` imports `roles.network.vendor.cloudflare`
directly so Cloudflare Zero Trust tooling stays host-scoped rather than polluting the shared profile.

## Reference Role: `roles.system.prospect`

- **Purpose:** snapshot the full workstation surface so Phase 4 parity checks can diff the new taxonomy against today’s System76 build.
- **Metadata:**

  ```nix
  metadata = {
    canonicalAppStreamId = "System";
    categories = [ "System" "Utility" ];
    auxiliaryCategories = [ "Settings" ];
    secondaryTags = [ "hardware-integration" "security" "virtualization" "cloudflare-zero-trust" ];
  };
  ```

- **Manifest:** generated via `nix eval .#nixosConfigurations.system76.config.environment.systemPackages --accept-flake-config --json` and stored at `docs/RFC-0001/workstation-packages.json`. Regenerate whenever the host configuration changes and re-run `nix build .#checks.x86_64-linux.phase4-workstation-parity --accept-flake-config` to confirm parity.
- **Vendor separation:** `roles.system.prospect` stays generic; vendor-specific payloads continue to live under `roles.system.vendor.<name>` so other hosts do not inherit System76-only software.

## Test Baseline (Phase 0)

Add these tests before refactoring so later phases must satisfy them:

- **Host package guard:** `checks/phase0/host-package-guard.sh`, surfaced via `nix build .#checks.x86_64-linux.phase0-host-package-guard --accept-flake-config`, confirms `environment.systemPackages` is sourced exclusively from roles (current allowlist derived from `roles.system.prospect`).
- **Profile purity:** `checks/phase0/profile-purity.nix`, surfaced via `nix build .#checks.x86_64-linux.phase0-profile-purity --accept-flake-config`, asserts that `profiles.workstation` imports only `roles.*` modules.
- **Alias resolver:** `checks/phase0/alias-resolver.nix`, surfaced via `nix build .#checks.x86_64-linux.phase0-alias-registry --accept-flake-config`, iterates every alias in this document and ensures it resolves to the canonical taxonomy path.
- **Taxonomy version guard:** `checks/phase0/taxonomy-version.nix`, surfaced via `nix build .#checks.x86_64-linux.phase0-taxonomy-version --accept-flake-config`, recomputes `TAXONOMY_VERSION` from the alias registry hash and fails if the constant is stale.
- **Metadata lint:** `checks/phase0/metadata-lint.nix`, surfaced via `nix build .#checks.x86_64-linux.phase0-metadata --accept-flake-config`, verifies that each role exports `canonicalAppStreamId`, `categories`, `secondaryTags`, and optional `auxiliaryCategories` values that the helper library can validate against the Freedesktop registry.
- **Role import inventory:** `scripts/list-role-imports.py`, surfaced via `nix build .#checks.x86_64-linux.phase0-role-imports --accept-flake-config`, ensures the reporter continues to parse modules correctly (CI uses the `--offline` mode).

Wire these into CI (i.e., `nix flake check --accept-flake-config`) so they gate later phases.
Ensure `modules/meta/ci.nix` continues to provide the runtime dependencies these derivations expect (e.g., `python3`, an explicit `${pkgs.bash}/bin/bash` invocation for the host guard) so the checks pass inside the Nix sandbox.

## Implementation Checklist

1. **Create tooling**
   - [x] Script to enumerate existing `flake.nixosModules.roles.*` exports and the packages they include.
   - [x] Lint to enforce `canonicalAppStreamId`, `categories`, `auxiliaryCategories`, and `secondaryTags` metadata, including validation against the upstream registry and controlled vocabularies.
   - [x] Wire `scripts/taxonomy-sweep.py` into local workflows so overrides regenerate from the manifest registry and emit the review queue.
2. **Define taxonomy scaffolding**
   - [x] Introduce helper library for category constants, AppStream registry validation, and secondary-tag vocabularies.
   - [x] Expose `TAXONOMY_VERSION` from the helper library and ensure `checks.phase0-taxonomy-version` depends on it.
   - [x] Add documentation page describing allowed categories and naming rules (`docs/taxonomy/role-taxonomy.md`).
3. **Add new roles**
   - [x] Create top-level directories matching canonical categories (e.g., `modules/roles/system`).
   - [x] Implement initial subroles (`system.storage`, `utility.archive`, `network.sharing`, etc.) populated with packages migrated from legacy roles.
   - [x] Stand up vendor namespaces as needed (`modules/roles/system/vendor/<vendor>/default.nix`) with metadata and imports mirroring the System76 example.
   - [x] Spin up `modules/profiles/<name>.nix` and migrate the existing workstation bundle to `profiles.workstation`, importing the new taxonomy roles instead of duplicating package lists.
   - [x] Split the legacy `dev` role into `roles.development.core` plus per-language bundles (`roles.development.python`, `roles.development.go`, etc.), ensuring each language bundle includes runtime, package manager, formatter, linter, and debugger/LSP defaults.
   - [x] Register stable alias mappings (`roles.dev`, `roles.dev.python`, `roles.dev.py`, etc.) that resolve to the new canonical roles and update `checks.phase0.alias-registry` accordingly.
4. **Update consumers**
   - [x] Point `profiles.workstation`, `configurations.nixos.system76`, and any other in-repo consumers directly at the new taxonomy roles.
   - [x] Capture before/after manifests to prove parity (e.g., `nix eval` diff of `environment.systemPackages` for `system76`). If the diff fails the future parity check, revert to the last Phase 2 commit, restore `workstation-packages.json`, and rerun Phase 0 checks before attempting the migration again.
   - [x] Add any new manifests to `docs/RFC-0001/manifest-registry.json` so the sweep script covers them automatically.
5. **Documentation updates**
   - [x] Update `docs/configuration-architecture.md`, role tables, and README references to reflect the taxonomy.
   - [ ] Publish migration notes (e.g., `docs/releases/next.md`).
   - [ ] Document the current `TAXONOMY_VERSION`, canonical categories, secondary-tag vocabulary, and available profiles for future contributors.
   - [x] Regenerate the `roles.system.prospect` package matrix (via `nix eval .#nixosConfigurations.system76.config.environment.systemPackages --accept-flake-config --json`) whenever the underlying configuration changes and re-run the Phase 4 parity check to ensure parity.
   - [x] Record the override review process and capture resolutions (commit or remove `build/taxonomy/metadata-overrides-review.json` once empty).
6. **Validation**
   - [x] Run `nix fmt`, `nix flake check`, `nix build .#checks.x86_64-linux.phase4-workstation-parity --accept-flake-config`, and targeted `nix eval` assertions to ensure role membership matches expectations.
   - [ ] Confirm no insecure allowances are lost during migration (Ventoy, etc.).
   - Phase 0 profile-purity guard now retains `_file` metadata during role flattening so canonical dotted roles and workstation helpers validate; `nix eval` confirms the sentinel passes.
   - Phase 0 host-package-guard now reports zero untracked packages. All workstation payloads—including the PipeWire/WirePlumber stack, gst/ffmpeg codecs, VPN helpers, nixos-\* tooling, nix-index, VSCode/vt-cli, libvirt/VMware/NVIDIA, and System76 vendor extras—flow through canonical roles or app modules.
   - `2025-10-14`: `nix develop -c nix flake check --accept-flake-config` passes end-to-end. The run produced `/nix/store/hd0fh8ly3m89689rphmxj9iv5mksi8qg-phase0-host-package-guard.drv`, `/nix/store/6drvxd53cjz5qc6cwbyf1zg6m0q55qjs-phase0-profile-purity-ok.drv`, and `/nix/store/fd4kvb4kz2h17dvm938y8sd8bkd0f6wj-phase0-metadata-ok.drv`, confirming Phase 0 guardrails remain green.

## Progress Tracking

- **Tooling foundation (Phase 0):** Complete. Metadata lint, taxonomy sweep automation, and the role import reporter (`scripts/list-role-imports.py`) are in place, documented, and enforced via the `phase0-role-imports` CI check.
- **Taxonomy scaffolding:** Helper library, alias hash guard, and version surfacing are finished; documentation work on allowed categories remains outstanding.
- **Phase 0 guardrails:** Host package guard, profile purity, alias registry, taxonomy version, metadata lint, and the role import inventory (`phase0-role-imports`) are all available under `nix build .#checks.x86_64-linux.phase0-*`. They intentionally fail until new roles land.
- **Role migration:** In progress. Canonical development, audio/video, network, office, utility, and science bundles now expose the migrated payloads; legacy shims have been removed. Outstanding work tracks the remaining niche bundles and Stage 3 parity tasks.
- **Consumer updates & parity:** Workstation now consumes canonical roles directly; host-specific parity snapshots and any remaining consumer flips (e.g., release/manifests) are staged for Stage 3.
- **Documentation refresh:** In progress. Implementation notes and the taxonomy reference reflect the canonical layout; release notes and parity documentation still need updates alongside the final migration steps.
