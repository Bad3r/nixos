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
still win. `shareCommon = false` is a deliberate opt-out.

This step cannot be forgotten: `modules/configurations/nixos.nix` aborts
evaluation for any host under `configurations.nixos` without an explicit
`shareCommon` entry, so `nix flake check` and every closure build fail until
the registry line exists.

## 2. Create the host module directory

Create `modules/<host>/` with the per-host file set. Every file contributes
to `configurations.nixos.<host>.module`; import-tree discovers the files
automatically, so no imports need registering. The minimal managed-workstation
footprint:

| File                  | Purpose                                                                                                                                                                     |
| --------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `hardware-config.nix` | Hardware truth from `nixos-generate-config`: filesystems, initrd modules, firmware, loader entry limit                                                                      |
| `host-id.nix`         | Unique `networking.hostId` (8 hex chars; derive with `head -c 8 /etc/machine-id` on the target)                                                                             |
| `state-version.nix`   | Install-time `system.stateVersion` constant; never bump on upgrades                                                                                                         |
| `policy.nix`          | Registry flags under `flake.lib.nixos.hosts.<host>` consumed by `modules/hosts/common/*` (see step 3)                                                                       |
| `ssh.nix`             | `services.openssh.publicKey` (the host ed25519 public key, consumed by `flake.nixosModules.ssh` for fleet known_hosts) and the enable choice                                |
| `imports.nix`         | Chassis-specific modules only (nixos-hardware profile, vendor support module); the fleet baseline comes from hosts-common                                                   |
| GPU module            | GPU wiring over `flake.nixosModules.nvidia-gpu` when the hardware has an NVIDIA GPU (`modules/system76/nvidia-gpu.nix`, `modules/tpnix/power.nix` are the current examples) |

Baseline behavior that does NOT need per-host files:

- `networking.hostName` is derived from the host directory name by
  `modules/hosts/common/hostname.nix`.
- The kernel defaults to `linuxPackages_zen` (`modules/hosts/common/boot.nix`,
  `lib.mkDefault`); add a per-host `boot.nix` only to override it.
- Firewall, networking base, duplicati wiring, tor client, and the app
  baseline are hosts-common modules parameterized by policy flags.

Common per-host divergence files, all optional:

| File               | Purpose                                                                                                                                                                                   |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `apps-enable.nix`  | App overrides at `lib.mkOverride 1000` over the common baseline; publish the override set under `flake.lib.nixos._hostAppsOverrides.<host>` so the FR-5 flake check rejects no-op entries |
| `default-apps.nix` | Per-host `host.defaults` overrides (audio player, video player)                                                                                                                           |
| `networking.nix`   | DNS or routing layered on the common NetworkManager base                                                                                                                                  |
| `nix-settings.nix` | Hardware-tuned `max-jobs` and `min-free` only                                                                                                                                             |
| `services.nix`     | Host-divergent services; on non-System76 hardware keep the default `powerprofilesctl` i3 power backend, System76 chassis override `gui.i3.powerProfiles.backend = "system76-power"`       |
| `support.nix`      | Vendor hardware-support enables (firmware daemon, kernel modules)                                                                                                                         |

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
    firewallDnsInterfaces = [ "<real-interface-name>" ];
    # firewallExtraTcpPortRanges = [ { from = 8000; to = 8999; } ];
    # duplicatiStateDirReadable = true;
  };
}
```

Use the host's real interface names (`ip link` on the target) for
`firewallDnsInterfaces`. If the new host becomes the primary fleet endpoint,
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
`nix eval .#nixosConfigurations --apply builtins.attrNames`, so the new host
is dry-run built on every compliance run and fully built in the nightly
update gate. Budget for the added nightly build time: update-flake builds
each host closure sequentially with garbage collection in between to respect
runner disk.

## 8. Validation ladder

```bash
nix fmt
nix flake check --accept-flake-config --no-build --offline
nix build ".#nixosConfigurations.<host>.config.system.build.toplevel"
./build.sh --host <host> --boot   # on the target machine
nix run .#generation-manager -- score   # target: 20/20
```

Run the first two before every push; the closure build proves the host
evaluates and compiles; `--boot` activates it on next reboot without
switching the running system.
