# System76 Home Manager Investigation – Key Events & Dependencies

The following timeline distils the most relevant checkpoints captured in `docs/system76-home-manager-observations.md`. Each entry highlights what changed or was discovered, along with the commands, modules, or inputs that the step depended on.

## Timeline

- **Initial failure scan – undated baseline**
  - **Finding:** `nix eval --accept-flake-config '.#nixosConfigurations.system76.config.home-manager'` only returned `home-manager.extraAppImports`; `config.home-manager.users` was missing entirely.
  - **Dependencies:** `modules/home-manager/nixos.nix` (no owner import executed); host evaluation lacked `_module.args.inputs` from `inputs.self`.
  - **Impact:** Established that the Home Manager glue never ran and that upstream inputs were not in scope.

- **Helper scope audit – undated baseline**
  - **Finding:** `_module.args.nixosRoleHelpers` and `_module.args.nixosAppHelpers` were absent during the System76 evaluation, even though the base bundle contained meta modules.
  - **Dependencies:** `modules/meta/nixos-role-helpers.nix`, `modules/meta/nixos-app-helpers.nix`, and the System76 import order defined in `modules/system76/imports.nix`.
  - **Impact:** Confirmed the helper injection never reached the host evaluation, explaining missing role/application wiring.

- **Meta helper reordering – undated baseline**
  - **Finding:** Adding `modules/meta/nixos-helpers.nix` (along with role/app helpers) to the meta stack allowed `_module.args.nixosRoleHelpers` to appear during base-only evaluation and exposed `config.flake.nixosModules.roles.ai-agents`.
  - **Dependencies:** `modules/meta/nixos-helpers.nix`, `modules/meta/nixos-roles-import.nix`; evaluation performed with the debug scaffold (`debug/system76-home-manager-scaffold.nix`).
  - **Impact:** Demonstrated the aggregator works when helpers run early, but highlighted that downstream imports still clobbered Home Manager options.

- **Import-tree ordering fix – 2025‑10‑22**
  - **Finding:** Normalised System76’s import stage to unwrap import-tree payloads before the workstation checks. `modules/system76/imports.nix` now uses a flattened `config.flake.nixosModules` view, letting lookups like `getModule "workstation"` succeed.
  - **Dependencies:** `modules/system76/imports.nix`, `inputs.import-tree`; evaluation verified via the scaffold and `nix eval --accept-flake-config '.#nixosConfigurations.system76.config.home-manager.users.vx'`.
  - **Impact:** Eliminated earlier “missing option `flake.nixosModules`” errors and moved the investigation to Home Manager namespace issues.

- **Home Manager guard relaxation – 2025‑10‑22**
  - **Finding:** Adjusted `modules/home-manager/nixos.nix` to treat override-wrapped modules as valid base definitions. The evaluation advanced past the previous “Home Manager base module missing” guard.
  - **Dependencies:** `modules/home-manager/nixos.nix`, `flake.homeManagerModules.base.imports`; tested with the System76 configuration eval command above.
  - **Impact:** Exposed the next blocker—`home-manager.users.<owner>.apps` was undefined after the guard passed.

- **GUI bundle deduplication – 2025‑10‑22**
  - **Finding:** Flattening `flake.homeManagerModules.gui.imports` and reworking `_user-bundles.nix` removed the duplicate `gui.i3.lockCommand` definitions. Evaluation then stalled on the missing `home-manager.users.<owner>.apps` option.
  - **Dependencies:** `_user-bundles.nix`, `modules/home-manager/nixos.nix`; validated with `nix eval --accept-flake-config '.#nixosConfigurations.system76.config.home-manager.users.vx'`.
  - **Impact:** Confirmed that bundling logic needed a new compatibility strategy (either legacy shims or a different aggregation point).

- **Plan revision (current work in progress)**
  - **Finding:** Directly pushing flatten bundles into `home-manager.sharedModules` without recreating legacy options still triggers the missing-option error because the raw import-tree attrsets expect `home-manager.users.<owner>.apps` to exist.
  - **Dependencies:** `modules/home-manager/nixos.nix` (flattening pipeline), System76 scaffold, evaluation command above.
  - **Impact:** Steering the next iteration toward constructing a wrapper module that imports concrete modules only, avoiding any implicit redefinition of Home Manager option namespaces.

## Cross-cutting Dependencies

- **Evaluation commands**
  - `nix eval --accept-flake-config '.#nixosConfigurations.system76.config.home-manager.users.vx'`
  - `nix eval --accept-flake-config '.#nixosConfigurations.system76.config.home-manager'`
  - Scaffold-driven `lib.evalModules` routines in `debug/system76-home-manager-scaffold.nix`

- **Key modules**
  - `modules/system76/imports.nix` – controls import-tree order and helper availability.
  - `modules/home-manager/nixos.nix` – gathers Home Manager modules, injects shared modules, and exposes owner configuration.
  - Meta helpers: `modules/meta/nixos-helpers.nix`, `modules/meta/nixos-role-helpers.nix`, `modules/meta/nixos-app-helpers.nix`.

These notes should make it easier to trace which change produced which effect without combing the full observations log. Update this file whenever new checkpoints land so it stays aligned with ongoing debugging.

## Diagram

```mermaid
graph TD
    A[Initial failure scan] --> B[Helper scope audit]
    B --> C[Meta helper reordering]
    C --> D[Import-tree ordering fix<br/>2025-10-22]
    D --> E[Home Manager guard relaxation<br/>2025-10-22]
    E --> F[GUI bundle deduplication<br/>2025-10-22]
    F --> G[Plan revision<br/>(current work in progress)]

    subgraph Commands & Tools
      H[`nix eval --accept-flake-config '.#nixosConfigurations.system76.config.home-manager.users.vx'`]
      I[debug/system76-home-manager-scaffold.nix]
    end

    subgraph Module Dependencies
      M1[modules/home-manager/nixos.nix]
      M2[modules/system76/imports.nix]
      M3[modules/meta/nixos-helpers.nix]
      M4[modules/meta/nixos-role-helpers.nix]
      M5[modules/meta/nixos-app-helpers.nix]
    end

    A --- H
    A --- M1
    B --- M3
    B --- M4
    B --- M5
    B --- M2
    C --- I
    C --- M3
    C --- M4
    C --- M5
    D --- M2
    D --- H
    E --- M1
    E --- H
    F --- M1
    F --- H
    G --- M1
    G --- H
```
