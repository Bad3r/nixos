# Host Composition

This document explains how host configurations are assembled from modules. Each host lives in its own `modules/<host>/` directory and feeds the `configurations.nixos.<host>` aggregator. To enumerate the active hosts at any time:

```bash
nix eval --accept-flake-config --json .#nixosConfigurations --apply builtins.attrNames
```

## Host Definition Pattern

Complete hosts live under `configurations.nixos.<name>.module`. The helper in `modules/configurations/nixos.nix` maps each entry to a `nixosConfigurations.<name>` output by wrapping the deferred module in `inputs.nixpkgs.lib.nixosSystem`.

```nix
# modules/system76/imports.nix (excerpt)
{ config, lib, inputs, ... }:
{
  configurations.nixos.system76.module = {
    imports =
      [
        config.flake.nixosModules.base
        config.flake.csec.wordlists
        config.flake.nixosModules.sopsRuntime
        config.flake.nixosModules.repoSecrets
        config.flake.nixosModules.lang
        config.flake.nixosModules.ssh
        inputs.nixos-hardware.nixosModules.system76
      ]
      ++ lib.optionals (lib.hasAttrByPath [ "flake" "nixosModules" "duplicati-r2" ] config) [
        config.flake.nixosModules."duplicati-r2"
      ]
      ++ lib.optionals (lib.hasAttrByPath [ "flake" "nixosModules" "mirror-root" ] config) [
        config.flake.nixosModules.mirror-root
      ]
      ++ lib.optionals (lib.hasAttrByPath [ "flake" "nixosModules" "system76-support" ] config) [
        config.flake.nixosModules.system76-support
      ];
  };
}
```

**Key points:**

- `configurations.nixos.<host>.module` is `lib.types.deferredModule` (declared in `modules/configurations/nixos.nix`).
- Optional imports are guarded with `lib.hasAttrByPath` + `lib.optionals` so a host evaluates even if a referenced module is gated out.
- Host composition uses aggregator names (`config.flake.nixosModules.*`, `config.flake.csec.*`), not literal file paths.
- Hardware profiles live under `inputs.nixos-hardware.nixosModules.<name>`. Use the most specific profile that exists upstream; do not invent suffixed names.

## Host File Structures

Every host follows the same shape: each `modules/<host>/*.nix` file extends `configurations.nixos.<host>.module`. Cross-host concerns (sudo, dbus, pipewire, hostname, sops, etc.) live under `modules/hosts/common/`; files present in each host directory (boot, networking, firewall, fonts, hardware-config, etc.) tend to mirror across hosts. Notable and divergent files are listed below for the hosts currently in the repo. To audit the current set of files for any host, run `ls modules/<host>/`.

### system76 (Oryx Pro laptop)

| File                                          | Purpose                                                                       |
| --------------------------------------------- | ----------------------------------------------------------------------------- |
| `modules/system76/imports.nix`                | Baseline module imports and hardware profile wiring                           |
| `modules/system76/home-manager-apps.nix`      | system76-only HM extras (awscli2, pentesting-devshell)                        |
| `modules/system76/nix-settings.nix`           | Hardware-tuned `max-jobs` and `min-free` overrides                            |
| `modules/system76/ssh.nix`                    | system76 host public key + `services.openssh.enable` override                 |
| `modules/system76/packages.nix`               | system76-hardware packages (system76-power, firmware, etc.)                   |
| `modules/system76/system76-power-overlay.nix` | `system76-power` patch overlay (host-specific)                                |
| `modules/system76/r2-runtime.nix`             | Host runtime bindings for external `r2-flake` modules                         |
| `modules/system76/hardware-config.nix`        | Filesystems, firmware, low-level hardware settings                            |
| `modules/system76/host-id.nix`                | `networking.hostId`                                                           |
| `modules/system76/support.nix`                | system76 hardware-support enable (kernel modules, firmware-daemon)            |
| `modules/system76/nvidia-gpu.nix`             | NVIDIA PRIME (system76-only)                                                  |
| `modules/system76/mpv.nix`                    | mpv `gpu-api = "opengl"` override (NVIDIA Vulkan deadlock workaround)         |
| `modules/system76/pass-secret-service.nix`    | DBus secret-service for `pass` (system76-only)                                |
| `modules/system76/policy.nix`                 | Registry data under `flake.lib.nixos.hosts.system76` (`primary`, `tailnetIp`) |
| `modules/system76/services.nix`               | Service-level host behavior                                                   |

### tpnix (ThinkPad)

| File                                     | Purpose                                                                                            |
| ---------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `modules/tpnix/imports.nix`              | Baseline module imports, gated on `flake.lib.nixos.hosts.tpnix.*` flags                            |
| `modules/tpnix/apps-enable.nix`          | Per-host overrides over the common app baseline                                                    |
| `modules/tpnix/home-manager-apps.nix`    | tpnix-only HM extras (libreoffice)                                                                 |
| `modules/tpnix/default-apps.nix`         | Per-host overrides for `host.defaults` (audioPlayer, videoPlayer = null)                           |
| `modules/tpnix/nix-settings.nix`         | Hardware-tuned `max-jobs` and `min-free` overrides                                                 |
| `modules/tpnix/firmware-manager-fix.nix` | tpnix-only `services.fwupd.enable = true;` override                                                |
| `modules/tpnix/fingerprint.nix`          | Fingerprint auth (`services.fprintd`) and PAM service wiring (tpnix-only)                          |
| `modules/tpnix/printing.nix`             | Printer provisioning with a SOPS-managed device URI (tpnix-only)                                   |
| `modules/tpnix/r2-runtime.nix`           | Host runtime bindings for external `r2-flake` modules                                              |
| `modules/tpnix/hardware-config.nix`      | Filesystems, firmware, low-level hardware settings                                                 |
| `modules/tpnix/host-id.nix`              | `networking.hostId`                                                                                |
| `modules/tpnix/support.nix`              | Stub for future tpnix hardware-support hooks                                                       |
| `modules/tpnix/policy.nix`               | Host-level policy flags exposed under `flake.lib.nixos.hosts.tpnix`                                |
| `modules/tpnix/power.nix`                | GPU, display, and power services (NVIDIA PRIME sync, `power-profiles-daemon`, logind lid handling) |
| `modules/tpnix/services.nix`             | Service-level host behavior                                                                        |

Cross-host baselines (default-apps, mirrors, nix-ld, sudo, zsh, ssh,
nix-substituters, packages, home-manager-apps, virtualization, ...) live in
`modules/hosts/common/` and contribute to `flake.nixosModules.hosts-common`.
The host constructor imports that aggregate before each host-specific module
when `flake.lib.nixos.hosts.<host>.shareCommon = true`.

General Nix daemon and evaluator settings live in `modules/base/nix-settings.nix`.
The common `nix-substituters` module owns cache topology and download retry
settings only. Per-host `nix-settings.nix` files stay limited to hardware-tuned
values such as `max-jobs` and `min-free`.

### Host-conditional helpers

When a module needs to behave differently for one host (or skip itself entirely), use `flake.lib.nixos.hosts.<hostname>.<flag>` rather than reading hostname strings. Example: `modules/tpnix/policy.nix` exports `flake.lib.nixos.hosts.tpnix.sopsRuntimeReady`, and `modules/tpnix/imports.nix` reads it before importing `duplicati-r2`.

```nix
inherit (config.flake.lib.nixos.hosts.tpnix) sopsRuntimeReady;
duplicatiModuleExists = sopsRuntimeReady && lib.hasAttrByPath [ "flake" "nixosModules" "duplicati-r2" ] config;
```

Add new host-conditional flags by declaring them under `flake.lib.nixos.hosts.<hostname>` in a host-owned module; consumers read the path with `lib.hasAttrByPath` to stay safe across hosts.

Registry entries also carry fleet endpoint data. `modules/system76/policy.nix` marks the host `primary = true` and records its `tailnetIp`; `modules/networking/ssh-hosts.nix` derives one `<host>.local` SSH alias per registered host (excluding self), and `modules/apps/tailscale.nix` defaults `sshHostName` to the primary host's `tailnetIp`. Promoting another host to primary is a policy.nix data change, not a module edit.

## App and Home Manager Wiring

Each host uses the same two-stage app model:

1. `modules/hosts/common/apps-base.nix` adds all discovered NixOS app modules
   (`getAllApps`) to the shared aggregate module.
2. `modules/hosts/common/apps-enable.nix` sets the per-app
   `programs.<name>.extended.enable` baseline at `lib.mkOverride 1100`.
   Host override files such as `modules/tpnix/apps-enable.nix` layer
   `lib.mkOverride 1000` overrides for entries where a host diverges.

Home Manager wiring follows the same shape:

- `modules/home-manager/nixos.nix` provides the shared HM base and default app imports for any host.
- `modules/<host>/home-manager-apps.nix` appends additional app keys via `home-manager.extraAppImports`.
- `modules/<host>/imports.nix` appends external shared modules (e.g. `inputs.r2-flake.homeManagerModules.default` on system76).

For integration-specific details of the external R2 module chain, see [`../r2-cloud/input-and-module-wiring.md`](../r2-cloud/input-and-module-wiring.md). For tpnix-specific implementation notes, see [`../tpnix/IMPLEMENTATION_PLAN.md`](../tpnix/IMPLEMENTATION_PLAN.md).

## Validation

After host-level changes, build every affected host closure and run flake-level checks. Substitute the host name(s) you actually touched:

```bash
nix build .#nixosConfigurations.<host>.config.system.build.toplevel
nix flake check --accept-flake-config --no-build --offline
nix run .#generation-manager -- score   # target: 20/20
```

Use `nix eval --accept-flake-config --json .#nixosConfigurations --apply builtins.attrNames` to enumerate the host names available in the current checkout.

## Next Steps

- [NixOS Modules](03-nixos-modules.md) -- available system modules
- [Home Manager](04-home-manager.md) -- wiring HM into hosts
- [Reference](06-reference.md) -- validation and troubleshooting
