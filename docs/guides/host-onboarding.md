# Host onboarding runbook

Procedure for adding a NixOS host to this repository.
The composition model behind these steps is in [Host Composition](../architecture/05-host-composition.md).
Commands below assume a linked worktree at the repository root, per the branch workflow in `CLAUDE.md`.

## Register the host and create its module directory

Precondition: a hostname is chosen, and no `modules/<host>/` directory exists yet.

1. Add the registry entry in `modules/hosts/common/registry.nix`:

   ```nix
   flake.lib.nixos.hosts.<host>.shareCommon = true;
   ```

   `shareCommon = true` imports the `hosts-common` aggregate before the host module; `false` is a deliberate opt-out, never a default.
   `modules/configurations/nixos.nix` throws for any host under `configurations.nixos` with no entry here, naming the exact line to add.

2. Create `modules/<host>/` with this file set; import-tree discovers every file automatically, with no import to register.

   | File                  | Purpose                                                 |
   | --------------------- | ------------------------------------------------------- |
   | `hardware-config.nix` | Filesystems and initrd from `nixos-generate-config`     |
   | `host-id.nix`         | `networking.hostId`, 8 hex chars from `/etc/machine-id` |
   | `state-version.nix`   | Install-time `system.stateVersion`, fixed forever       |
   | `policy.nix`          | Registry flags hosts-common reads (next section)        |
   | `imports.nix`         | Chassis-specific modules only                           |
   | `nix-settings.nix`    | `max-jobs`, `min-free`, `max-substitution-jobs`         |

   `networking.hostName` and the default kernel package already come from hosts-common; add a per-host file only to override them.
   `nix-settings.nix` is not optional: `modules/hosts/common/nix-substituters.nix` asserts `max-substitution-jobs` is an integer at least 1 on every `shareCommon` host, since Nix has no `auto` for it; pin `nproc - 1`.
   `modules/<host>/ssh.nix` waits for first boot, since `modules/configurations/nixos.nix` throws on a `services.openssh.publicKey` with no `fleetHostKeys` pin.
   That file also carries the host's `services.openssh.enable` choice, but `modules/networking/ssh.nix` sets `enable = true` at default priority, so a plain `false` there is a conflicting definition that fails the host's evaluation and `lib.mkDefault false` loses to it; opting out takes `lib.mkForce false`.
   [Host secrets and handoff](host-onboarding-secrets.md) adds the key and its pin together.

3. Add per-host divergence files only where the host actually diverges:

   | File               | Purpose                                                    |
   | ------------------ | ---------------------------------------------------------- |
   | `apps-enable.nix`  | App overrides through `flake.lib.hostApps.mk`              |
   | `default-apps.nix` | Per-host `host.defaults` overrides                         |
   | `networking.nix`   | DNS, routing, pinned interface names                       |
   | `services.nix`     | Host-divergent services                                    |
   | `support.nix`      | Vendor firmware and kernel modules                         |
   | GPU module         | `gpu.nvidia.*` wiring, named per host, if the host has one |

   [Songbird configuration](../songbird/songbird-configuration.md) is a finished example of this layout.
   The `apps-enable.nix` override pattern, including the no-op check that rejects redundant entries, is in [Apps Module Style Guide](apps-module-style-guide.md).
   Unfree packages go through `nixpkgs.allowedUnfreePackages` in `modules/meta/nixpkgs-allowed-unfree.nix`; the same option inside a host module fails evaluation.

Verification: `nix flake check path:. --accept-flake-config --no-build --offline` passes the registry check in `modules/configurations/nixos.nix` and stops at the absent `firewallDnsInterfaces` key, which the next section sets.

## Set the policy flags

Precondition: `modules/<host>/policy.nix` exists with a `flake.lib.nixos.hosts.<host>` attrset.

1. Set the two firewall keys that `modules/hosts/common/firewall.nix` requires on every `shareCommon` host:

   ```nix
   firewallDnsInterfaces = [ ];
   firewallLocalTcpPortRanges = [ ];
   ```

   Leave `firewallDnsInterfaces` empty unless the host actually serves DNS or DHCP; a non-empty entry opens inbound UDP 53/67 and TCP 53 on those interfaces.
   `firewallLocalTcpPortRanges` scopes to `10.0.0.0/8` and `192.168.0.0/16` IPv4 sources; `firewallExtraTcpPortRanges` opens a range globally instead.
   `shareCommon` hosts boot with `net.ifnames=0`, so `firewall.nix` asserts on an `enp*` or `wlp*` name here and warns on an unpinned kernel name such as `eth0`.
   [Pin an interface name](../networking/README.md#pin-an-interface-name) in the networking guide gives the `.link` procedure.

2. Set `cacheRoots.nvidiaKernelModules` to `true` or `false` the moment the host loads the `nvidia` driver.
   `modules/meta/cache-roots.nix` throws for an NVIDIA-enabled host that leaves the key unset or non-Boolean, or that sets an unknown `cacheRoots` key.
   [Binary Cache Coverage](../reference/binary-cache-coverage.md) covers the tradeoff behind each value.

3. Leave `sopsRuntimeReady` and any runtime gate such as `r2RuntimeReady` at `false` until the age identity and its secrets exist.
   Hosts-common modules read these with an `or false` default, so an untouched gate simply stays off until the next guide flips it.

Verification: `nix flake check path:. --accept-flake-config --no-build --offline` reports no unknown-key or missing-Boolean throw from `modules/meta/cache-roots.nix` or `modules/hosts/common/firewall.nix`.

## Validation ladder

Precondition: the host is registered, with a module directory and policy flags in place.

1. Format and check the flake:

   ```sh
   nix run path:.#treefmt -- .
   nix flake check path:. --accept-flake-config --no-build --offline
   ```

2. Build the host closure:

   ```sh
   nix build "path:.#nixosConfigurations.<host>.config.system.build.toplevel"
   ```

3. Commit the host's files and land them on the branch the target checks out, then boot the generation from that checkout on the target machine without switching its running system:

   ```sh
   NH_BYPASS_ROOT_CHECK=1 nix --extra-experimental-features "nix-command flakes" shell nixpkgs#git nixpkgs#nh -c ./build.sh --bootstrap --skip-hooks --allow-dirty --host <host> --boot
   ```

   A freshly installed target ships no `git`, which `--allow-dirty` needs for `build.sh`'s secrets guard, and enables no experimental features, so both landing that checkout and running this command need the `nix shell nixpkgs#git nixpkgs#nh` wrapper shown above; [Songbird runbook: reinstall](../songbird/songbird-runbook-reinstall.md) works through this exact case end to end.
   `--allow-dirty` returns early from `build.sh`'s clean-tree guard, so the commit is on the reader: `path:` builds the target's working tree, and an uncommitted host module activates here while reaching no other checkout.
   A linked worktree selects `path:` on its own, and on a primary checkout `--allow-dirty` selects it in place of the bare `git+file` reference, which would pull the private submodule the target has no credentials for.
   `path:` copies `secrets/` as it finds it instead of excluding it, and a linked worktree here inherits this repository's already-initialized submodule, so it stages `sops.secrets."act/github_token"`; `modules/security/secrets.nix` declares that secret on `builtins.pathExists` alone, with no `sopsRuntimeReady` gate, so the new host's first boot fails sops-nix activation before [Host secrets and handoff](host-onboarding-secrets.md) installs the age identity.
   Land the target's checkout instead as a clone made without `--recurse-submodules`, per [Songbird runbook: reinstall](../songbird/songbird-runbook-reinstall.md), which keeps `secrets/` empty through this step.
   `--bootstrap` replaces the substituter list with the fleet caches before `modules/hosts/common/nix-substituters.nix` activates, and `--skip-hooks` drops the `pre-commit run --all-files` stage that would build the whole devshell first; `nix flake check` still runs.
   `NH_BYPASS_ROOT_CHECK=1` is required because `nh os` refuses to run as an effective uid of 0, and a freshly installed target has no other account to run it from.
   `modules/meta/owner.nix` declares the owner account, so this same activation creates it; no manual user setup precedes it.

4. Score Dendritic Pattern compliance:

   ```sh
   nix run path:.#generation-manager -- score
   ```

[Songbird runbook: reinstall](../songbird/songbird-runbook-reinstall.md) works through this same ladder for one host, starting at its first switch after a reinstall.

Verification: the target machine reboots into the new generation, and step 1's flake check reports no assertion failures for the new host.

## Register the host outside the module tree

Precondition: the host boots through the ladder above.

1. Create the GitHub label, since no label-sync config exists, and add its row to the Host Labels table in [GitHub Labels](../reference/github-labels.md):

   ```sh
   gh label create "host(<host>)" --color 5319E7 --description "Specific to the <host> host or its runtime contract."
   ```

2. Add `<host>` to the pages that enumerate hosts by name:
   `docs/index.md`, `docs/ONBOARDING.md`, `docs/architecture/01-pattern-overview.md`, `docs/architecture/03-nixos-modules.md`, `docs/architecture/04-home-manager.md`, and `docs/architecture/05-host-composition.md`.

3. No workflow edits are needed. `.github/workflows/check.yml` and `.github/workflows/update-flake.yml` derive the host list from `nix eval --accept-flake-config --json "path:.#nixosConfigurations" --apply builtins.attrNames`, so the new host is covered without touching either. `check.yml` only forces each host's `system.build.toplevel.drvPath` through `nix eval`, not `nix build --dry-run`, because Lix forces read-only store mode for `--dry-run` and that breaks eval-time store writes on the fresh runner; a compliance run proves the host evaluates to a derivation, not that its closure builds or substitutes. `update-flake.yml` is what builds each host closure, one at a time with `nix store gc` between hosts to respect runner disk.

Verification: `gh label list --search 'host('` includes `host(<host>)`, and `rg -l -w <host> docs/` lists every page above.

Install the age identity, provision secrets, pin the SSH host key, and hand off the primary role in [Host secrets and handoff](host-onboarding-secrets.md).
