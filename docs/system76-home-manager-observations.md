# System76 Home Manager Integration – Current Findings

## Summary

System76’s NixOS host does import the workstation bundle and the System76‑specific overlays, but the Home Manager glue never succeeds. As a result the evaluated configuration only exposes the `home-manager.extraAppImports` knob, and no Home Manager users or defaults are generated.

## Key Observations

- `nix eval --accept-flake-config '.#nixosConfigurations.system76.config.home-manager'` returns an attrset with just `extraAppImports`, confirming the broader Home Manager config never materialises.
- Querying `config.home-manager.users` via  
  `nix eval --accept-flake-config --impure --expr 'let flake = builtins.getFlake (toString ./.) ; in flake.nixosConfigurations.system76.config.home-manager.users'`  
  fails with `attribute 'users' missing`; the owner import from `modules/home-manager/nixos.nix` never ran.
- The module args visible during host evaluation omit flake inputs:  
  `nix eval --accept-flake-config '.#nixosConfigurations.system76._module.args' --apply builtins.attrNames`  
  → `[ "baseModules" "extendModules" "extraModules" "moduleType" "modules" "noUserModules" "pkgs" "utils" ]`.
- `_module.specialArgs` confirms only the default `modulesPath` is passed through (`nix eval … '_module.specialArgs'`), so no `inputs`/`self` reach downstream modules.
- `modules/system76/imports.nix` builds `nixosConfigurations.system76` by calling `inputs.nixpkgs.lib.nixosSystem { modules = [ … config.configurations.nixos.system76.module ]; }` without any `specialArgs`. Because of that, the module system never seeds `_module.args.inputs`, and the Home Manager glue’s lookup of `flake.homeManagerModules.base` fails.
- Inspecting `flake.outputs.nixosModules.base` directly shows the Home Manager glue is already missing **before** the role helper runs: every entry— including `modules/home-manager/nixos.nix`—exposes only `_file` and `imports`, with no `flake.homeManagerModules` or `config.home-manager` payload. This confirms the loss happens upstream of the role sanitisation.

## Consequence

With `_module.args.inputs` empty, `modules/home-manager/nixos.nix` cannot locate the aggregated Home Manager modules. The default user stanza throws, short‑circuiting option registration, leaving only whichever attributes the System76 overlays append (e.g., `extraAppImports`/`sharedModules`).

## Scratch Reproduction

Evaluating the live module list via `lib.evalModules` shows that injecting `specialArgs = { inputs = flake.inputs; self = flake; }` **alone** does not restore the missing options: both the original evaluation and the instrumented rerun still produce a `config.home-manager` attrset with only `extraAppImports`. This means the attrset is being overwritten (or never populated) later in the module chain, not simply blocked by missing `specialArgs`.

A dedicated scaffold (`debug/system76-home-manager-scaffold.nix`) now recreates the System76 import stack with option stubs and per-module traces. The trace output shows every System76 import (including the “pre-system76” checkpoint) observing only `home-manager = { extraAppImports = … }`, so the attrset is already collapsed before any of the System76 overlays execute. The culprit therefore lies in the shared `flake.nixosModules.base` pipeline.

## Next Investigation Steps

1. Extend the scaffold to the base aggregator and pinpoint the exact module under `flake.nixosModules.base` that drops the Home Manager keys.
2. Once the culprit is identified, decide whether to feed flake inputs there, merge instead of overwrite, or rearrange imports.
