# Host Composition

This document explains how host configurations are assembled from modules. Each host lives in its own `modules/<host>/` directory and feeds the `configurations.nixos.<host>` aggregator. To enumerate the active hosts at any time:

```bash
nix eval --accept-flake-config --json .#nixosConfigurations --apply builtins.attrNames
```

## Host Definition Pattern

Complete hosts live under `configurations.nixos.<name>.module`. The helper in `modules/configurations/nixos.nix` maps each entry to a `nixosConfigurations.<name>` output by wrapping the deferred module in `inputs.nixpkgs.lib.nixosSystem`.

Fleet-shared composition lives in `modules/hosts/common/imports.nix`, which contributes the aggregate import list (base, sops runtime, repo secrets, lang, ssh, shared hardware profiles, optional modules) to `flake.nixosModules.hosts-common`. Host-owned composition files carry chassis-specific modules when needed; `modules/system76/imports.nix` is the current example:

```nix
# modules/hosts/common/imports.nix (excerpt)
{ config, lib, inputs, ... }:
{
  flake.nixosModules.hosts-common.imports = [
    config.flake.nixosModules.base
    config.flake.nixosModules.sopsRuntime
    config.flake.nixosModules.repoSecrets
    inputs.nixos-hardware.nixosModules.common-cpu-intel-cpu-only
  ]
  ++ lib.optionals (lib.hasAttrByPath [ "flake" "nixosModules" "duplicati-r2" ] config) [
    config.flake.nixosModules."duplicati-r2"
  ];
}

# modules/system76/imports.nix (excerpt)
{ config, lib, inputs, ... }:
{
  configurations.nixos.system76.module = {
    imports = [
      inputs.nixos-hardware.nixosModules.system76
    ]
    ++ lib.optionals (lib.hasAttrByPath [ "flake" "nixosModules" "system76-support" ] config) [
      config.flake.nixosModules.system76-support
    ];
  };
}
```

**Key points:**

- `configurations.nixos.<host>.module` is `lib.types.deferredModule` (declared in `modules/configurations/nixos.nix`).
- Fleet-shared imports and baselines contribute to `flake.nixosModules.hosts-common`; the host constructor imports that aggregate before the host module for every registry entry with `shareCommon = true`, so per-host overrides still win.
- Optional imports are guarded with `lib.hasAttrByPath` + `lib.optionals` so a host evaluates even if a referenced module is gated out.
- Host composition uses aggregator names (`config.flake.nixosModules.*`, `config.flake.csec.*`), not literal file paths.
- Hardware profiles live under `inputs.nixos-hardware.nixosModules.<name>`. Use the most specific profile that exists upstream; do not invent suffixed names.

## Host File Structures

Every host follows the same shape: NixOS fragments under `modules/<host>/` extend `configurations.nixos.<host>.module`, while `policy.nix` contributes per-host registry data. Cross-host concerns (imports skeleton, boot, base services, networking base, firewall, fonts, duplicati wiring, sudo, dbus, pipewire, hostname, sops, etc.) live under `modules/hosts/common/`; a host directory carries only hardware truth, chassis-specific modules, and small value files. Notable and divergent files are listed below for the hosts currently in the repo. To audit the current set of files for any host, run `ls modules/<host>/`.

The planned `songbird` managed-workstation footprint is `hardware-config.nix`,
`host-id.nix`, `state-version.nix`, a GPU module, `support.nix`, and a
`policy.nix` carrying the registry values the common layer consumes. Every
host additionally needs an explicit `shareCommon` entry in
`modules/hosts/common/registry.nix`: the host constructor aborts evaluation
for hosts without one, so common-baseline participation is always a recorded
choice (`true` to opt in, `false` to deliberately opt out). The full
procedure lives in the [host onboarding runbook](../guides/host-onboarding.md).

### system76 (Oryx Pro laptop)

| File                                          | Purpose                                                                                                          |
| --------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `modules/system76/imports.nix`                | System76-chassis modules (nixos-hardware profile, system76-support) and host-specific enables                    |
| `modules/system76/nix-settings.nix`           | Hardware-tuned `max-jobs` and `min-free` overrides                                                               |
| `modules/system76/ssh.nix`                    | system76 host public key + `services.openssh.enable` override                                                    |
| `modules/system76/packages.nix`               | system76-hardware packages (system76-power, firmware, etc.)                                                      |
| `modules/system76/system76-power-overlay.nix` | `system76-power` patch overlay (host-specific)                                                                   |
| `modules/system76/r2-runtime.nix`             | Host runtime bindings for external `r2-flake` modules, gated on the `r2RuntimeReady` registry flag               |
| `modules/system76/hardware-config.nix`        | Filesystems, firmware, loader entry limit, low-level hardware settings                                           |
| `modules/system76/host-id.nix`                | `networking.hostId`                                                                                              |
| `modules/system76/state-version.nix`          | Install-time `system.stateVersion` constant                                                                      |
| `modules/system76/support.nix`                | system76 hardware-support enable (kernel modules, firmware-daemon)                                               |
| `modules/system76/nvidia-gpu.nix`             | GPU profile over `flake.nixosModules.nvidia-gpu` (`system76.gpu.mode` enum, libva routing, NVIDIA kernel params) |
| `modules/system76/mpv.nix`                    | mpv `gpu-api = "opengl"` override (NVIDIA Vulkan deadlock workaround)                                            |
| `modules/system76/pass-secret-service.nix`    | DBus secret-service for `pass` (system76-only)                                                                   |
| `modules/system76/policy.nix`                 | Registry data under `flake.lib.nixos.hosts.system76` (`primary`, `tailnetIp`, readiness gates, per-host values)  |
| `modules/system76/services.nix`               | Host-divergent services (Samba media share, system76-power stack, cloudflared, LACT)                             |

### tpnix (ThinkPad)

| File                                     | Purpose                                                                                                                         |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `modules/tpnix/apps-enable.nix`          | Per-host overrides over the common app baseline                                                                                 |
| `modules/tpnix/default-apps.nix`         | Per-host overrides for `host.defaults` (audioPlayer, videoPlayer = null)                                                        |
| `modules/tpnix/nix-settings.nix`         | Hardware-tuned `max-jobs` and `min-free` overrides                                                                              |
| `modules/tpnix/firmware-manager-fix.nix` | tpnix-only `services.fwupd.enable = true;` override                                                                             |
| `modules/tpnix/fingerprint.nix`          | Fingerprint auth (`services.fprintd`) and PAM service wiring (tpnix-only)                                                       |
| `modules/tpnix/fonts.nix`                | Arabic fontconfig rules through the `host.fontconfig.extraRules` option                                                         |
| `modules/tpnix/networking.nix`           | SignalX DNS routing layered on the common NetworkManager base                                                                   |
| `modules/tpnix/printing.nix`             | Printer provisioning with a SOPS-managed device URI (tpnix-only)                                                                |
| `modules/tpnix/r2-runtime.nix`           | Host runtime bindings for external `r2-flake` modules, gated on the `r2RuntimeReady` registry flag                              |
| `modules/tpnix/hardware-config.nix`      | Filesystems, firmware, loader entry limit, low-level hardware settings                                                          |
| `modules/tpnix/host-id.nix`              | `networking.hostId`                                                                                                             |
| `modules/tpnix/state-version.nix`        | Install-time `system.stateVersion` constant                                                                                     |
| `modules/tpnix/support.nix`              | Stub for future tpnix hardware-support hooks                                                                                    |
| `modules/tpnix/policy.nix`               | Registry data under `flake.lib.nixos.hosts.tpnix` (readiness gates, per-host values)                                            |
| `modules/tpnix/power.nix`                | GPU profile over `flake.nixosModules.nvidia-gpu` plus display and power services (`power-profiles-daemon`, logind lid handling) |
| `modules/tpnix/services.nix`             | Host-divergent services (printing, power-profiles-daemon stack, espanso X11 override)                                           |

Cross-host baselines (imports skeleton, boot, base services, networking base, firewall, fonts, duplicati wiring, color-profile, default-apps, mirrors, nix-ld, sudo, zsh, ssh, nix-substituters, packages, home-manager-apps, virtualization, ...) live in `modules/hosts/common/` and contribute to `flake.nixosModules.hosts-common`. The host constructor imports that aggregate before each host-specific module when `flake.lib.nixos.hosts.<host>.shareCommon = true`.

General Nix daemon and evaluator settings live in `modules/base/nix-settings.nix`.
The common `nix-substituters` module owns cache topology and download retry
settings only. Per-host `nix-settings.nix` files stay limited to hardware-tuned
values such as `max-jobs` and `min-free`.

### Host-conditional helpers

When a module needs to behave differently for one host (or skip itself entirely), use `flake.lib.nixos.hosts.<hostname>.<flag>` rather than reading hostname strings. Example: `modules/tpnix/policy.nix` exports `flake.lib.nixos.hosts.tpnix.sopsRuntimeReady`, and `modules/hosts/common/duplicati.nix` reads it before enabling `services.duplicati-r2` for that host.

Common modules read per-host registry data inside their deferred module body, keyed by the `hostName` module argument:

```nix
{ config, ... }:
let
  hostsRegistry = config.flake.lib.nixos.hosts or { };
  body =
    { hostName, lib, ... }:
    {
      networking.firewall.allowedTCPPortRanges =
        (hostsRegistry.${hostName} or { }).firewallExtraTcpPortRanges or [ ];
    };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
```

Add new host-conditional flags by declaring them under `flake.lib.nixos.hosts.<hostname>` in the host's `policy.nix`; consumers read the path with `lib.hasAttrByPath` or `or` fallbacks to stay safe across hosts. Current per-host value keys consumed by `modules/hosts/common/*`: `sopsRuntimeReady`, `duplicatiStateDirReadable`, `lenovoMonitorAttached`, `extraHomeApps`, `firewallDnsInterfaces`, and `firewallExtraTcpPortRanges`. Each host's `r2-runtime.nix` reads its own `r2RuntimeReady` gate before calling the shared R2 helper.

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
- `modules/hosts/common/home-manager-apps.nix` imports the shared app and browser set and appends host-only extras from the `extraHomeApps` registry list.
- `modules/<host>/r2-runtime.nix` binds the external R2 module chain per host.

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
