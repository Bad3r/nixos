# Host Onboarding Runbook

Procedural checklist for adding a NixOS host to this repository. The
composition model behind these steps is documented in
[Host Composition](../architecture/05-host-composition.md); hardware planning
for the next host lives in
[project-songbird](../songbird/project-songbird.md). Follow the steps in
order: the validation ladder at the end assumes everything before it is in
place.

## 1. Register the host

Add an explicit entry to `modules/hosts/common/registry.nix`:

```nix
flake.lib.nixos.hosts.<host>.shareCommon = true;
```

`shareCommon = true` imports the entire `flake.nixosModules.hosts-common`
aggregate (hostname, boot defaults, networking base, firewall, sops runtime,
app baseline, state defaults) before the host module, so per-host overrides
still win. `shareCommon = false` is a deliberate opt-out. The host constructor
still imports the Nixpkgs insecure-package policy before this branch, so an
explicitly imported app module can use
`nixpkgs.extraPermittedInsecurePackages` without depending on `hosts-common`.

This step cannot be forgotten: `modules/configurations/nixos.nix` aborts
evaluation for any host under `configurations.nixos` without an explicit
`shareCommon` entry, so `nix flake check` and every closure build fail until
the registry line exists.

## 2. Create the host module directory

Create `modules/<host>/` with the per-host file set. Every file contributes
to `configurations.nixos.<host>.module`; import-tree discovers the files
automatically, so no imports need registering. The minimal managed-workstation
footprint:

| File                  | Purpose                                                                                                                                                                                                                                           |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `hardware-config.nix` | Hardware truth from `nixos-generate-config`: filesystems, initrd modules, firmware, loader entry limit                                                                                                                                            |
| `host-id.nix`         | Unique `networking.hostId` (8 hex chars; derive with `head -c 8 /etc/machine-id` on the target)                                                                                                                                                   |
| `state-version.nix`   | Install-time `system.stateVersion` constant; never bump on upgrades                                                                                                                                                                               |
| `policy.nix`          | Registry flags under `flake.lib.nixos.hosts.<host>` consumed by `modules/hosts/common/*` (see step 3)                                                                                                                                             |
| `ssh.nix`             | `services.openssh.publicKey` (the host ed25519 public key, consumed by `flake.nixosModules.ssh` for fleet known_hosts) and the enable choice                                                                                                      |
| `imports.nix`         | Chassis-specific modules only (nixos-hardware profile, vendor support module); the fleet baseline comes from hosts-common                                                                                                                         |
| GPU module            | GPU wiring over `flake.nixosModules.nvidia-gpu` when the hardware has an NVIDIA GPU (`modules/system76/nvidia-gpu.nix`, `modules/tpnix/power.nix` are the current examples); pairs with the `cacheRoots.nvidiaKernelModules` policy key in step 3 |
| `nix-settings.nix`    | Hardware-tuned `max-jobs` and `min-free`, plus `max-substitution-jobs` (`nproc - 1`, floored at 1; Nix has no `auto` for it), which `modules/hosts/common/nix-substituters.nix` asserts on every `shareCommon` host                               |

Baseline behavior that does NOT need per-host files:

- `networking.hostName` is derived from the host directory name by
  `modules/hosts/common/hostname.nix`.
- The kernel defaults to `linuxPackages_zen` (`modules/hosts/common/boot.nix`,
  `lib.mkDefault`); add a per-host `boot.nix` only to override it.
- Firewall, networking base, duplicati wiring, tor client, and the app
  baseline are hosts-common modules parameterized by policy flags.

Common per-host divergence files, all optional:

| File               | Purpose                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `apps-enable.nix`  | App overrides at `lib.mkOverride 1000` over the common baseline; publish the flat set under `flake.lib.nixos._hostAppsOverrides.<host>` so the FR-5 flake check rejects no-op entries. A nested toggle (`claude-code.extended.installMethods.bun.enable`) cannot go through that set: register it under `flake.lib.nixos._hostAppsSubToggleOverrides.<host>` as `{ path; value; }` and build the override by folding that list, per the [apps module style guide](apps-module-style-guide.md) |
| `default-apps.nix` | Per-host `host.defaults` overrides (audio player, video player)                                                                                                                                                                                                                                                                                                                                                                                                                               |
| `networking.nix`   | DNS or routing layered on the common NetworkManager base                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `services.nix`     | Host-divergent services; on non-System76 hardware keep the default `powerprofilesctl` i3 power backend, System76 chassis override `gui.i3.powerProfiles.backend = "system76-power"`                                                                                                                                                                                                                                                                                                           |
| `support.nix`      | Vendor hardware-support enables (firmware daemon, kernel modules)                                                                                                                                                                                                                                                                                                                                                                                                                             |

Unfree packages are declared at the flake-parts level only (the
`nixpkgs.allowedUnfreePackages` option declared in
`modules/meta/nixpkgs-allowed-unfree.nix`, contributed from any module).
There is no NixOS-scope allowlist: setting `nixpkgs.allowedUnfreePackages`
inside the host module fails evaluation.

## 3. Fill in policy.nix

`policy.nix` publishes per-host registry data read by `modules/hosts/common/*`
and fleet consumers. Start conservative and flip gates as the host becomes
ready:

```nix
_: {
  flake.lib.nixos.hosts.<host> = {
    # Gate for sops-consuming common modules. Keep false until the age
    # identity is installed on the machine (step 4), then flip to true.
    sopsRuntimeReady = false;

    # Gate read by modules/<host>/r2-runtime.nix, if the host binds the
    # external R2 module chain.
    r2RuntimeReady = false;

    # Values consumed by modules/hosts/common/*.
    extraHomeApps = [ ];
    firewallDnsInterfaces = [ ]; # Required. See below before opening DNS/DHCP.
    firewallLocalTcpPortRanges = [ ]; # Required. See below before exposing services.
    # Globally reachable TCP range on every firewall interface.
    # firewallExtraTcpPortRanges = [ { from = 8000; to = 8999; } ];
    # duplicatiStateDirReadable = true;
    # secrets/<host>.yaml keys holding hosts(5) payloads that dnsmasq serves
    # as addn-hosts files (modules/hosts/common/private-dns-hosts.nix).
    # privateDnsHostsSecretKeys = [ "internal_hosts" ];

    # Required on an NVIDIA host: modules/meta/cache-roots.nix throws without
    # it. true publishes the built kernel module as a cache root, false keeps
    # a module with no substituter local. See below.
    # cacheRoots.nvidiaKernelModules = true;
  };
}
```

`firewallDnsInterfaces` and `firewallLocalTcpPortRanges` are required:
`modules/hosts/common/firewall.nix` throws when either key is absent, so a
misspelling cannot silently remove the rules it controls. Leave
`firewallDnsInterfaces` empty unless the host actually serves DNS or DHCP to
the network. It opens inbound UDP 53/67 and
TCP 53, and NetworkManager's `dns = "dnsmasq"` mode is not a reason to set it:
that dnsmasq is a caching resolver NetworkManager binds to `127.0.0.1` and
`::1` with no `dhcp-range`, so it never listens on a link.

`cacheRoots.nvidiaKernelModules` becomes required the moment the host loads
the `nvidia` video driver, which the GPU module in step 2 does:
`modules/meta/cache-roots.nix` throws for an NVIDIA-enabled host that leaves
it unset or non-Boolean, and for any host whose `cacheRoots` carries an
unknown key, and the `cache-roots-nvidia-cache-policy` flake check forces
that policy for every registered host, so `nix flake check` fails before the
host builds. `true`
publishes the built kernel module among the cache roots the fleet pushes;
`false` records an exclusion for a module no substituter serves, which is
songbird's case with its source-built CachyOS kernel.
`docs/reference/binary-cache-coverage.md` covers the policy.

`firewallExtraTcpPortRanges` opens a range globally. In contrast,
`firewallLocalTcpPortRanges` emits IPv4 `iptables` rules that accept source
addresses in only `10.0.0.0/8` and `192.168.0.0/16`. It excludes
`172.16.0.0/12`, IPv6, and any stronger trusted-network assertion, so choose
the global key only for intentional public reachability and the source-scoped
key only when those exact CIDRs are the intended access boundary. Set
`firewallLocalTcpPortRanges = [ ];` explicitly when no source-scoped TCP range
is wanted.

When the host does have such a listener, pin the intended device with a `.link`
`Name=` and use the pinned name. `shareCommon` hosts boot with `net.ifnames=0`,
so an unpinned device carries `eth0`, `eth1`, or `wlan0` rather than the `enp*`
and `wlp*` names an installer shows, and those numbers follow discovery order.
`modules/hosts/common/firewall.nix` rejects an `enp*`/`wlp*` name on such a host
with an assertion, warns when a name is neither kernel-assigned nor created by a
declaration on the host, and warns on a kernel-assigned name with no pin behind
it. That last warning clears as soon as a pin backs the entry. What no guard
catches is a pinned or kernel name that is simply wrong for this machine: that
emits a `networking.firewall.interfaces.<name>` entry for a device that never
appears, so the opening silently does nothing.

On a host with two interfaces of the same class, or with a removable adapter,
the `eth0` and `eth1` numbering follows kernel discovery order and can move
between devices. Do not point `firewallDnsInterfaces` at a name that can
change: the rule opens UDP 53/67 and TCP 53 on whichever device holds the name
that boot. Pin the intended device first, as `modules/tpnix/networking.nix`
does, then use the pinned name:

```sh
ip -br link
for dev in /sys/class/net/*; do
  udevadm info -q property -p "$dev" \
    | grep -E '^(INTERFACE|ID_NET_DRIVER|ID_PATH)='
done
```

```nix
_: {
  configurations.nixos.<host>.module = {
    systemd.network.links."10-uplink0" = {
      matchConfig.Path = "<ID_PATH value>";
      linkConfig = {
        # Outside the kernel's own eth*/wlan* pools: systemd.link(5) calls a
        # pin named eth0 a race against the kernel's own assignment.
        Name = "uplink0";
        # The pin displaces 99-default.link for this device, so restore the
        # alternative names it would otherwise supply. Its "mac" token is left
        # out: that derives an altname from the factory hardware address.
        AlternativeNamesPolicy = "database onboard slot path";
      };
    };
  };
}
```

The block above is for a device with no `.link` yet. When one already matches
it, as `modules/songbird/networking.nix` and `modules/system76/networking.nix`
do for every NIC, add `Name=` to that entry and delete its `NamePolicy=` rather
than adding a second file: udev applies only the first matching file, so a new
one renames nothing while `pinnedNamesOf` still counts its `Name=` as a declared
name. `modules/hosts/common/firewall.nix` also rejects duplicate names on
device-specific pins and broad, empty, globbed, or multi-valued matches that
precede another enabled `.link`. It asserts against a second `.link` for a
device that already has one and a single file carrying `Name=` and
`NamePolicy=` together, so following this section without those steps fails
`nix flake check`.

A device that needs no pinned name still wants that last line, because
`net.ifnames=0` gates the rename only and leaves `99-default.link`'s `mac`
token generating an `enx<permanent-mac>` altname. Drop `Name=`, add
`NamePolicy = "keep kernel database onboard slot path"` in its place, and keep
`AlternativeNamesPolicy`, as `modules/songbird/networking.nix` does for all
three of its NICs.

`docs/networking/README.md` covers why the pinned name stays outside the
kernel's `eth*` namespace, why the match uses the path rather than a MAC, and
why `NamePolicy` belongs in the second shape but never in a pin.

If the new host becomes the primary fleet endpoint,
move `primary = true` and `tailnetIp` from the current primary host's
`policy.nix`: `modules/networking/ssh-hosts.nix` aliases and the tailscale
SSH default follow that registry data automatically.

## 4. Provision secrets (sops)

`modules/hosts/common/imports.nix` already imports
`flake.nixosModules.sopsRuntime` and `flake.nixosModules.repoSecrets` for
every `shareCommon` host; no per-host sops wiring is needed.

1. Install the single canonical age identity on the machine, following
   Host Preparation in [SOPS usage](../sops/README.md): the private key goes
   to `/var/lib/sops-nix/key.txt` (system) and `~/.config/sops/age/keys.txt`
   (Home Manager). Single-recipient design: no `.sops.yaml` change and no
   `sops updatekeys`.
2. Flip `sopsRuntimeReady = true` in `policy.nix` once the identity is in
   place.
3. Add `secrets/<host>.yaml` in the secrets submodule only if the host needs
   host-specific secrets (the catch-all creation rule in `.sops.yaml` already
   matches). Guard every new `sops.secrets` declaration with the
   `builtins.pathExists` pattern so secretless CI evaluation keeps working.
4. Push the secrets submodule before evaluating or opening a PR:
   `self.submodules = true` pins `secrets/` by revision, so an unpushed
   submodule commit fails `nix flake check` and CI with
   `Cannot find Git revision`.

## 5. Backups (duplicati)

`modules/hosts/common/duplicati.nix` enables `services.duplicati-r2`
automatically once the duplicati module and secrets exist and
`sopsRuntimeReady` is true; `duplicatiStateDirReadable = true` additionally
grants the owner read access to the state directory. Confirm the source
paths in the shared `secrets/duplicati-config.json` manifest exist on the new
host; a manifest that references only absent paths yields a silently idle
backup timer.

## 6. Documentation and labels

- Update the host-enumerating docs: `docs/index.md`, `docs/ONBOARDING.md`,
  `docs/architecture/01-pattern-overview.md`,
  `docs/architecture/03-nixos-modules.md`,
  `docs/architecture/04-home-manager.md`,
  `docs/architecture/05-host-composition.md`, and
  `docs/reference/github-labels.md`.
- Create the GitHub label manually (no label-sync config exists):
  `gh label create "host(<host>)" --color <hex> --description "<host> host"`.

## 7. CI

No workflow edits are needed: `.github/workflows/check.yml` and
`.github/workflows/update-flake.yml` derive the host list from
`nix eval "path:.#nixosConfigurations" --apply builtins.attrNames`, so the new host
is dry-run built on every compliance run and fully built in the nightly
update gate. Budget for the added nightly build time: update-flake builds
each host closure sequentially with garbage collection in between to respect
runner disk.

## 8. Validation ladder

```bash
nix run path:.#treefmt -- .
nix flake check path:. --accept-flake-config --no-build --offline
nix build "path:.#nixosConfigurations.<host>.config.system.build.toplevel"
./build.sh --host <host> --boot   # on the target machine
nix run path:.#generation-manager -- score   # target: 20/20
```

Run the first two before every push; the closure build proves the host
evaluates and compiles; `--boot` activates it on next reboot without
switching the running system.
