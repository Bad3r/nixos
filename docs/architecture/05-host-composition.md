# Host Composition

## Host Definition Pattern

Complete hosts live under `configurations.nixos.<name>.module`. The helper in `modules/configurations/nixos.nix` maps each entry to a `nixosConfigurations.<name>` output by wrapping the deferred module in `inputs.nixpkgs.lib.nixosSystem`.

Fleet-shared composition lives in `modules/hosts/common/imports.nix`, which contributes the aggregate import list (base, sops runtime, repo secrets, ssh, shared hardware profiles, optional modules) to `flake.nixosModules.hosts-common`. Host-owned composition files extend `configurations.nixos.<host>.module` directly for anything that does not belong in the shared aggregate, as `modules/hosts/songbird/support.nix` does:

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

# modules/hosts/songbird/support.nix (excerpt)
_: {
  configurations.nixos.songbird.module = {
    services.fwupd.enable = true;
  };
}
```

- `configurations.nixos.<host>.module` is `lib.types.deferredModule` (declared in `modules/configurations/nixos.nix`).
- Fleet-shared imports and baselines contribute to `flake.nixosModules.hosts-common`; the host constructor imports that aggregate before the host module for every registry entry with `shareCommon = true`, so per-host overrides still win.
- Optional imports are guarded with `lib.hasAttrByPath` + `lib.optionals` so a host evaluates even if a referenced module is gated out.
- Host composition uses aggregator names (`config.flake.nixosModules.*`, `config.flake.csec.*`), not literal file paths.
- Hardware profiles live under `inputs.nixos-hardware.nixosModules.<name>`. Use the most specific profile that exists upstream; do not invent suffixed names.

## Host File Inventory

[Host File Inventory](host-file-inventory.md) records the host directory contract, shared ownership boundaries, and host-specific files.

## Host-conditional helpers

When a module needs to behave differently for one host (or skip itself entirely), use `flake.lib.nixos.hosts.<hostname>.<flag>` rather than reading hostname strings. Example: `modules/hosts/songbird/policy.nix` exports `flake.lib.nixos.hosts.songbird.sopsRuntimeReady`, and `modules/hosts/common/duplicati.nix` reads it before enabling `services.duplicati-r2` for that host.

Common modules read per-host registry data inside their deferred module body, keyed by the `hostName` module argument:

```nix
{ config, ... }:
let
  hostsRegistry = config.flake.lib.nixos.hosts or { };
  body =
    { hostName, lib, ... }:
    let
      hostFlags = hostsRegistry.${hostName} or { };
    in
    {
      networking.firewall.allowedTCPPortRanges =
        hostFlags.firewallExtraTcpPortRanges or [ ];
    };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
```

`firewallExtraTcpPortRanges` maps to NixOS's normal globally reachable TCP ranges. `firewallLocalTcpPortRanges` is separate: `modules/hosts/common/firewall.nix` emits IPv4 `iptables` rules for sources in `10.0.0.0/8` and `192.168.0.0/16`. On a host that enables `cloudflare-warp`, it opens the same ranges on `CloudflareWARP` to every Mesh device. It neither includes `172.16.0.0/12` nor establishes an IPv6 or trusted-network boundary.

Add new host-conditional flags by declaring them under `flake.lib.nixos.hosts.<hostname>` in the host's `policy.nix`; consumers use `lib.hasAttrByPath` or `or` fallbacks only where absence is intentional. Current per-host value keys consumed by shared modules or `modules/meta/cache-roots.nix`: `sopsRuntimeReady`, `duplicatiStateDirReadable`, `firewallExtraTcpPortRanges`, `firewallLocalTcpPortRanges`, `cloudflareWarpMeshAddressReady`, `rustdeskServer`, and `cacheRoots`. `cacheRoots.nvidiaKernelModules` is a Boolean required on every NVIDIA-enabled host: `true` publishes the installed module and `false` excludes it. Missing, empty, non-Boolean, or unknown cache-root policy values fail evaluation. Each host's `r2-runtime.nix` reads its own `r2RuntimeReady` gate before calling the shared R2 helper.
`rustdeskServer` marks the one host that runs hbbs and hbbr; with none or several, [RustDesk](../usage/rustdesk.md) stays off everywhere and each RustDesk-enabled host warns.

Cloudflare Mesh endpoints stay encrypted in `secrets/cloudflare-warp.yaml` and render as local `<host>.internal` mappings after their registry entry sets `cloudflareWarpMeshAddressReady`; see [WARP on the fleet](../apps/cloudflare/warp/README.md).
The Tailscale `primary` and `tailnetIp` mechanism remains separate and permits at most one primary.

## App and Home Manager Wiring

Each host uses the same two-stage app model:

1. `modules/hosts/common/apps-base.nix` adds all discovered NixOS app modules
   (`getAllApps`) to the shared aggregate module.
2. `modules/hosts/common/apps-enable.nix` sets the per-app
   `programs.<name>.extended.enable` baseline at `lib.mkOverride 1100`.
   Host override files such as `modules/hosts/songbird/apps-enable.nix` layer
   `lib.mkOverride 1000` overrides for entries where a host diverges.
   Nested overrides register full paths and route through `programs` first,
   falling back to `services` for services-only paths. Paths absent from both
   namespaces fail the host evaluation, so a switch cannot drop them silently;
   the shared FR-5 check reports them as well.

Home Manager wiring follows the same shape:

- `modules/home-manager/nixos.nix` provides the shared HM base for any host.
- `modules/hosts/common/home-manager-apps.nix` imports every Home Manager app and browser module on every host; each gates on its app row, its own enable option, or the NixOS setting it configures.
- `modules/hosts/<host>/r2-runtime.nix` binds the external R2 module chain per host.

For integration-specific details of the external R2 module chain, see [`../apps/r2-cloud/input-and-module-wiring.md`](../apps/r2-cloud/input-and-module-wiring.md).

## Validation

After host-level changes, run this chain from the repository root to inventory ignored paths, list active hosts, and validate every affected host:

```bash
git status --porcelain --ignored=matching &&
  git submodule foreach --recursive 'git status --porcelain --ignored=matching' &&
  bash -c 'source scripts/lib/secrets-guard.sh && secrets_guard_enforce "$PWD" "path:$PWD"' &&
  nix eval --accept-flake-config --json "path:.#nixosConfigurations" --apply builtins.attrNames &&
  nix build "path:.#nixosConfigurations.<host>.config.system.build.toplevel" &&
  nix flake check path:. --accept-flake-config --no-build --offline
```
