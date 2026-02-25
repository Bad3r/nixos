# Host Composition

This document explains how the host configuration is assembled from modules.

## Host Definition Pattern

Complete hosts live under `configurations.nixos.<name>.module`. The helper in `modules/configurations/nixos.nix` maps these to `nixosConfigurations.<name>` outputs.

```nix
# modules/system76/imports.nix
{ config, lib, inputs, ... }:
{
  configurations.nixos.system76.module = {
    imports =
      [
        config.flake.nixosModules.base
        config.flake.nixosModules.lang
        config.flake.nixosModules.ssh
      ]
      ++ lib.optionals (lib.hasAttrByPath [ "flake" "nixosModules" "system76-support" ] config) [
        config.flake.nixosModules."system76-support"
      ]
      ++ [
        inputs.nixos-hardware.nixosModules.system76
        inputs.nixos-hardware.nixosModules.system76-darp6
      ];
  };
}
```

**Key points:**

- `configurations.nixos.<host>.module` is `lib.types.deferredModule`
- Optional imports are guarded with `lib.hasAttrByPath` + `lib.optionals`
- Host composition uses aggregator names (`config.flake.nixosModules.*`), not literal file paths

## System76 Host Structure

The System76 host is composed by many files that all extend `configurations.nixos.system76.module`:

| File                                           | Purpose                                               |
| ---------------------------------------------- | ----------------------------------------------------- |
| `modules/system76/imports.nix`                 | Baseline module imports and hardware profile wiring   |
| `modules/system76/apps-base.nix`               | Imports all discovered NixOS app modules              |
| `modules/system76/apps-enable.nix`             | Per-app enable/disable defaults                       |
| `modules/system76/home-manager-apps.nix`       | Extra HM app imports and shared module wiring         |
| `modules/system76/default-apps.nix`            | XDG default application selection + env vars          |
| `modules/system76/custom-packages-overlay.nix` | Injects local `packages/*` into host `pkgs` overlay   |
| `modules/system76/r2-runtime.nix`              | Host runtime bindings for external `r2-flake` modules |
| `modules/system76/hardware-config.nix`         | Filesystems, firmware, low-level hardware settings    |
| `modules/system76/nvidia-gpu.nix`              | NVIDIA PRIME configuration                            |
| `modules/system76/services.nix`                | Service-level host behavior                           |

## App and Home Manager Wiring

This repo uses a two-stage app model:

1. `modules/system76/apps-base.nix` imports all discovered NixOS app modules (`getAllApps`)
2. `modules/system76/apps-enable.nix` toggles per-app `programs.<name>.extended.enable`

Home Manager is wired similarly:

- `modules/home-manager/nixos.nix` provides HM base + default app imports
- `modules/system76/home-manager-apps.nix` appends additional app keys via `home-manager.extraAppImports`
- `modules/system76/imports.nix` appends external shared modules such as `inputs.r2-flake.homeManagerModules.default`

For integration-specific details of the external R2 module chain, see
[`../r2-cloud/input-and-module-wiring.md`](../r2-cloud/input-and-module-wiring.md).

## Single-Host Repository Policy

Although the architecture can represent multiple hosts, this repository intentionally manages only one host: `system76`. Do not add new hosts unless repository policy changes.

## Validation

After host-level changes, run:

```bash
nix build .#nixosConfigurations.system76.config.system.build.toplevel
nix flake check --accept-flake-config --no-build --offline
nix run .#generation-manager -- score   # target: 35/35
```

## Next Steps

- [NixOS Modules](03-nixos-modules.md) -- available system modules
- [Home Manager](04-home-manager.md) -- wiring HM into hosts
- [Reference](06-reference.md) -- validation and troubleshooting
