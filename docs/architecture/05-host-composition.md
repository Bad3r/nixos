# Host Composition

This document explains how hosts are defined and assembled from modules.

## Host Definition Pattern

Complete hosts live under `configurations.nixos.<name>.module`. The helper in `modules/configurations/nixos.nix` transforms these into `nixosConfigurations.<name>` outputs.

```nix
# modules/system76/imports.nix
{ config, lib, ... }:
{
  configurations.nixos.system76.module = {
    imports = lib.filter (module: module != null) [
      (config.flake.nixosModules.base or null)
      (config.flake.nixosModules."system76-support" or null)
      (config.flake.nixosModules."hardware-lenovo-y27q-20" or null)
    ];
  };
}
```

**Key points:**

- Use `or null` + `lib.filter` to handle optional modules gracefully
- Reference modules by aggregator name, never by file path
- The `configurations.nixos.<host>.module` type is `lib.types.deferredModule`

## System76 Host Structure

The System76 host demonstrates the pattern:

| File                                    | Purpose                                 |
| --------------------------------------- | --------------------------------------- |
| `modules/system76/imports.nix`          | Collects baseline modules, exports host |
| `modules/system76/boot.nix`             | Kernel, crash dump, NVIDIA params       |
| `modules/system76/hardware-config.nix`  | Filesystems, LUKS, firmware             |
| `modules/system76/nvidia-gpu.nix`       | NVIDIA PRIME configuration              |
| `modules/system76/services.nix`         | power management, scheduler             |
| `modules/system76/packages.nix`         | System76 utilities                      |
| `modules/system76/home-manager-gui.nix` | HM GUI integration                      |

Each file extends `configurations.nixos.system76.module` directly:

```nix
# modules/system76/services.nix
_: {
  configurations.nixos.system76.module = {
    services.system76-scheduler.enable = true;
    # ...
  };
}
```

## Adding a New Host

### Checklist

1. **Create host directory:**

   ```bash
   mkdir modules/<hostname>
   ```

2. **Create imports.nix:**

   ```nix
   # modules/<hostname>/imports.nix
   { config, lib, ... }:
   {
     configurations.nixos.<hostname>.module = {
       imports = lib.filter (m: m != null) [
         (config.flake.nixosModules.base or null)
         # Add hardware profiles, etc.
       ];
     };

     # Export to nixosConfigurations
     flake.nixosConfigurations.<hostname> =
       config.configurations.nixos.<hostname>.nixosConfiguration;
   }
   ```

3. **Add host-specific files:**
   - `hardware-config.nix` — filesystems, boot devices
   - `boot.nix` — kernel, bootloader
   - etc.

4. **Verify the graph builds:**

   ```bash
   nix eval .#nixosConfigurations.<hostname>.config.system.build.toplevel
   ```

5. **Run validation:**
   ```bash
   nix flake check --accept-flake-config
   ```

## Importing App Modules

Use the app registry helpers to import apps:

```nix
{ config, ... }:
{
  configurations.nixos.<hostname>.module.imports =
    config.flake.lib.nixos.getApps [
      "firefox"
      "steam"
      "obs-studio"
    ];
}
```

## Migration from Legacy Configs

When adopting an existing NixOS configuration:

1. **Split into feature modules** under `modules/<domain>/`
2. **Export each feature** under `flake.nixosModules.<name>`
3. **Replace literal imports** with aggregator references:

   ```nix
   # Before
   imports = [ ./networking.nix ./audio.nix ];

   # After
   imports = [
     config.flake.nixosModules.networking
     config.flake.nixosModules.audio
   ];
   ```

4. **Define the host** under `configurations.nixos.<host>.module`
5. **Validate** with `generation-manager score` (target: 90/90)

## Next Steps

- [NixOS Modules](03-nixos-modules.md) — available system modules
- [Home Manager](04-home-manager.md) — wiring HM into hosts
- [Reference](06-reference.md) — validation commands
