# Host Composition

Host configurations assemble modules from each `modules/<host>/` directory through the `configurations.nixos.<host>` aggregator.

## Host Definition Pattern

Complete hosts live under `configurations.nixos.<name>.module`. The helper in `modules/configurations/nixos.nix` maps each entry to a `nixosConfigurations.<name>` output by wrapping the deferred module in `inputs.nixpkgs.lib.nixosSystem`.

Fleet-shared composition lives in `modules/hosts/common/imports.nix`, which contributes the aggregate import list (base, sops runtime, repo secrets, lang, ssh, shared hardware profiles, optional modules) to `flake.nixosModules.hosts-common`. Host-owned composition files extend `configurations.nixos.<host>.module` directly for anything that does not belong in the shared aggregate; `modules/songbird/imports.nix` is the current example:

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

# modules/songbird/imports.nix (excerpt)
_: {
  configurations.nixos.songbird.module = {
    languages = {
      clojure.extended.enable = true;
      rust.extended.enable = true;
      java.extended.enable = true;
      python.extended.enable = true;
      go.extended.enable = true;
    };
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

When a module needs to behave differently for one host (or skip itself entirely), use `flake.lib.nixos.hosts.<hostname>.<flag>` rather than reading hostname strings. Example: `modules/tpnix/policy.nix` exports `flake.lib.nixos.hosts.tpnix.sopsRuntimeReady`, and `modules/hosts/common/duplicati.nix` reads it before enabling `services.duplicati-r2` for that host.

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

`firewallExtraTcpPortRanges` maps to NixOS's normal globally reachable TCP ranges. `firewallLocalTcpPortRanges` is separate: `modules/hosts/common/firewall.nix` emits IPv4 `iptables` rules for source addresses in `10.0.0.0/8` and `192.168.0.0/16` only. It neither includes `172.16.0.0/12` nor establishes an IPv6 or trusted-network boundary.

Add new host-conditional flags by declaring them under `flake.lib.nixos.hosts.<hostname>` in the host's `policy.nix`; consumers use `lib.hasAttrByPath` or `or` fallbacks only where absence is intentional. Current per-host value keys consumed by shared modules or `modules/meta/cache-roots.nix`: `sopsRuntimeReady`, `duplicatiStateDirReadable`, `lenovoMonitorAttached`, `extraHomeApps`, `firewallDnsInterfaces`, `firewallExtraTcpPortRanges`, `firewallLocalTcpPortRanges`, `privateDnsHostsSecretKeys`, and `cacheRoots`. `firewallDnsInterfaces` and `firewallLocalTcpPortRanges` are exceptions to the fallback rule: `modules/hosts/common/firewall.nix` throws when either is absent, so every host must set both explicitly. `firewallDnsInterfaces = [ ];` means the host serves no DNS or DHCP; `firewallLocalTcpPortRanges = [ ];` means it exposes no source-scoped TCP range. A misspelled key would otherwise silently omit the rules it controls. `cacheRoots.nvidiaKernelModules` is a Boolean required on every NVIDIA-enabled host: `true` publishes the installed module and `false` excludes it. Missing, empty, non-Boolean, or unknown cache-root policy values fail evaluation. Each host's `r2-runtime.nix` reads its own `r2RuntimeReady` gate before calling the shared R2 helper.

### Private DNS Host Pinning

Internal name-to-IP mappings stay encrypted instead of living in the public
system config. `modules/hosts/common/private-dns-hosts.nix` turns every key
listed in `flake.lib.nixos.hosts.<host>.privateDnsHostsSecretKeys` into a sops
secret at `/run/secrets/<host>/networking/private-hosts/<key>` (underscores in
the key become hyphens in the runtime path, so `signalx_hosts` lands at
`.../private-hosts/signalx-hosts`) and serves it through NetworkManager's
dnsmasq:

```nix
# modules/<host>/policy.nix
privateDnsHostsSecretKeys = [ "signalx_hosts" ];
```

Each key holds a hosts(5) payload (`<ip> <name> [alias...]` per line) in
`secrets/<host>.yaml`. Adding more internal hosts is a secrets edit; adding a
second source is one more key in the list. Keys must stay distinct after the
hyphen rewrite: declaring `internal_hosts` alongside `internal-hosts` fails an
assertion instead of collapsing into one secret and dropping a payload. The
module then sets
`networking.networkmanager.dns = "dnsmasq"`, disables `services.resolved`, and
writes `/etc/NetworkManager/dnsmasq.d/private-hosts.conf` with one
`addn-hosts=` line per key. Hosts that declare no keys stay untouched. A host
that declares keys while `sopsRuntimeReady = false` (the onboarding default) or
before `secrets/<host>.yaml` exists gets none of this either: the module emits a
warning and leaves the host on `systemd-resolved` until both are in place.

NetworkManager spawns dnsmasq without `--user`, so the snippet pins
`user=nm-dnsmasq` / `group=nm-dnsmasq` and each secret is `root:nm-dnsmasq`
mode `0440`, readable after the privilege drop and on SIGHUP re-reads.
`systemd.services.NetworkManager.restartTriggers` carries the snippet plus each
secret's ownership triple, because sops-nix restarts units only when decrypted
bytes change.

Registry entries also carry fleet endpoint data. `modules/songbird/policy.nix` marks the host `primary = true` and records its `tailnetIp`; `modules/networking/ssh-hosts.nix` derives one `<host>.local` SSH alias per registered host (excluding self), and `modules/apps/tailscale.nix` defaults `sshHostName` to the primary host's `tailnetIp`. At most one registry host may be primary, while no primary leaves the default unset. Promoting another host is a policy.nix data change, not a module edit. Each host carrying the fleet SSH config must then switch because Home Manager renders the primary alias at build time.

## App and Home Manager Wiring

Each host uses the same two-stage app model:

1. `modules/hosts/common/apps-base.nix` adds all discovered NixOS app modules
   (`getAllApps`) to the shared aggregate module.
2. `modules/hosts/common/apps-enable.nix` sets the per-app
   `programs.<name>.extended.enable` baseline at `lib.mkOverride 1100`.
   Host override files such as `modules/tpnix/apps-enable.nix` layer
   `lib.mkOverride 1000` overrides for entries where a host diverges.
   Nested overrides register full paths and route through `programs` first,
   falling back to `services` for services-only paths. Paths absent from both
   namespaces fail the host evaluation, so a switch cannot drop them silently;
   the shared FR-5 check reports them as well.

Home Manager wiring follows the same shape:

- `modules/home-manager/nixos.nix` provides the shared HM base and default app imports for any host.
- `modules/hosts/common/home-manager-apps.nix` imports the shared app and browser set and appends host-only extras from the `extraHomeApps` registry list.
- `modules/<host>/r2-runtime.nix` binds the external R2 module chain per host.

For integration-specific details of the external R2 module chain, see [`../r2-cloud/input-and-module-wiring.md`](../r2-cloud/input-and-module-wiring.md). For tpnix-specific implementation notes, see [`../tpnix/IMPLEMENTATION_PLAN.md`](../tpnix/IMPLEMENTATION_PLAN.md).

## Validation

After host-level changes, run both ignored-path inventories in [Reference](06-reference.md), require the shared guard below, then build every affected host closure and run flake-level checks:

```bash
bash -c 'source scripts/lib/secrets-guard.sh && secrets_guard_enforce "$PWD" "path:$PWD"' &&
  nix build "path:.#nixosConfigurations.<host>.config.system.build.toplevel"
nix flake check path:. --accept-flake-config --no-build --offline
nix run path:.#generation-manager -- score   # target: 20/20
```

Use `nix eval --accept-flake-config --json "path:.#nixosConfigurations" --apply builtins.attrNames` to enumerate the host names available in the current checkout.
