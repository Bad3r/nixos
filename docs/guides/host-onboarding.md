# Host onboarding runbook

Procedure for adding a NixOS host to this repository; its composition model is in [Host Composition](../architecture/05-host-composition.md).
Commands below assume a linked worktree at the repository root, per the branch workflow in `CLAUDE.md`, except on the target machine: the validation ladder's boot step needs a clone made without `--recurse-submodules`, as that step explains.
Define `guarded_nix` in every shell used below; each call inventories ignored paths and requires the shared guard from [Reference](../architecture/06-reference.md) to pass before Nix starts. Benign inventory output may appear.

```sh
guarded_nix() { git status --porcelain --ignored=matching &&
  git submodule foreach --recursive 'git status --porcelain --ignored=matching' &&
  bash -c 'source scripts/lib/secrets-guard.sh && secrets_guard_enforce "$PWD" "path:$PWD"' &&
  command nix "$@"; }
```

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
   | `nix-settings.nix`    | `max-jobs`, `min-free`, `max-substitution-jobs`         |
   | `ssh.nix`             | Explicit SSH enable choice; public key added after boot |

   `networking.hostName` and the default kernel package already come from hosts-common; add a per-host file only to override them.
   `nix-settings.nix` is not optional: `modules/hosts/common/nix-substituters.nix` asserts `max-substitution-jobs` is an integer at least 1 on every `shareCommon` host, since Nix has no `auto` for it; pin `nproc - 1`.
   Create `modules/<host>/ssh.nix` now with a plain `services.openssh.enable = true` when remote first-boot administration is required, or `false` when local-console access makes it unnecessary.
   Without that explicit choice, `modules/networking/ssh.nix` defaults sshd on with `lib.mkDefault true`.
   The hosts-common firewall is independent: `false` stops sshd while its TCP 22 rules for `tailscale0` and `10.0.0.0/8` remain.
   Only `services.openssh.publicKey` waits for first boot; [Host secrets and handoff](host-onboarding-secrets.md) adds the generated key and its `fleetHostKeys` pin together.

3. Add per-host divergence files only where the host actually diverges:

   | File               | Purpose                                                    |
   | ------------------ | ---------------------------------------------------------- |
   | `apps-enable.nix`  | App overrides through `flake.lib.hostApps.mk`              |
   | `default-apps.nix` | Per-host `host.defaults` overrides                         |
   | `networking.nix`   | DNS, routing, pinned interface names                       |
   | `services.nix`     | Host-divergent services                                    |
   | `support.nix`      | Vendor firmware and kernel modules                         |
   | `imports.nix`      | Host-only module imports or grouped toolchain enables      |
   | GPU module         | `gpu.nvidia.*` wiring, named per host, if the host has one |

   The `apps-enable.nix` override pattern, including the no-op check that rejects redundant entries, is in [Apps Module Style Guide](apps-module-style-guide.md).
   Unfree packages go through `nixpkgs.allowedUnfreePackages` in `modules/meta/nixpkgs-allowed-unfree.nix`; the same option inside a host module fails evaluation.

Verification: `guarded_nix flake check path:. --accept-flake-config --no-build --offline` passes the registry check in `modules/configurations/nixos.nix` and stops at the absent `firewallDnsInterfaces` key, which the next section sets.

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

Verification: `guarded_nix flake check path:. --accept-flake-config --no-build --offline` reports no unknown-key or missing-Boolean throw from `modules/meta/cache-roots.nix` or `modules/hosts/common/firewall.nix`.

## Validation ladder

Precondition: the host is registered, with a module directory and policy flags in place.

1. Format and check the flake:

   ```sh
   guarded_nix run path:.#treefmt -- . &&
     guarded_nix flake check path:. --accept-flake-config --no-build --offline
   ```

2. Build the host closure:

   ```sh
   guarded_nix build "path:.#nixosConfigurations.<host>.config.system.build.toplevel"
   ```

3. Commit the host's files and land them on the branch the target checks out, then boot the generation from that checkout on the target machine without switching its running system:

   ```sh
   NH_BYPASS_ROOT_CHECK=1 nix --extra-experimental-features "nix-command flakes" shell nixpkgs#git nixpkgs#nh -c ./build.sh --bootstrap --skip-hooks --allow-dirty --host <host> --boot
   ```

   A freshly installed target ships no `git`, which `--allow-dirty` needs for `build.sh`'s secrets guard, and enables no experimental features, so both landing that checkout and running this command need the `nix shell nixpkgs#git nixpkgs#nh` wrapper shown above; [Songbird runbook: reinstall](../songbird/songbird-runbook-reinstall.md) works through this exact case end to end.
   `--allow-dirty` returns early from `build.sh`'s clean-tree guard, so the commit is on the reader: `path:` builds the target's working tree, and an uncommitted host module activates here while reaching no other checkout.
   A linked worktree selects `path:` on its own, and on a primary checkout `--allow-dirty` selects it in place of the bare `git+file` reference, which would pull the private submodule the target has no credentials for.
   `path:` copies `secrets/` as it finds it instead of excluding it; `git worktree add` does not initialize submodules on its own, but this repository's `post-checkout` hook (`modules/development/git-hooks-post-checkout.nix`) runs `git submodule update --init --recursive` on the checkout `git worktree add` performs.
   A linked worktree sharing this repository's `core.hooksPath` therefore carries `secrets/act.yaml`; `modules/security/secrets.nix` declares `sops.secrets."act/github_token"` when that file exists and `security.repoSecrets.enable` retains the common `lib.mkDefault true`, without consulting `sopsRuntimeReady`.
   A plain `security.repoSecrets.enable = false;` host override suppresses that declaration and the repo-gated rclone declarations, but other common system and Home Manager secret modules have independent enables.
   The override cannot make a fully populated `secrets/` submodule safe without the age identity; if used for a targeted bootstrap, remove it after both age identity copies are installed and before the secret-bearing rebuild in [Host secrets and handoff](host-onboarding-secrets.md).
   Land the target's checkout instead as a clone made without `--recurse-submodules`, per [Songbird runbook: reinstall](../songbird/songbird-runbook-reinstall.md), which keeps `secrets/` empty through this step.
   `--bootstrap` replaces the substituter list with the fleet caches before `modules/hosts/common/nix-substituters.nix` activates, and `--skip-hooks` drops the `pre-commit run --all-files` stage that would build the whole devshell first; `nix flake check` still runs.
   `NH_BYPASS_ROOT_CHECK=1` is required because `nh os` refuses to run as an effective uid of 0, and a freshly installed target has no other account to run it from.
   `modules/meta/owner.nix` declares the owner account, so this same activation creates it; no manual user setup precedes it.

4. Score Dendritic Pattern compliance:

   ```sh
   guarded_nix run path:.#generation-manager -- score
   ```

[Songbird runbook: reinstall](../songbird/songbird-runbook-reinstall.md) works through this same ladder for one host, starting at its first switch after a reinstall.

Verification: the target machine reboots into the new generation, and step 1's flake check reports no assertion failures for the new host.

## Register the host outside the module tree

Precondition: the host boots through the ladder above.

1. Create the GitHub label, since no label-sync config exists, and add its row to the Host Labels table in [GitHub Labels](../reference/github-labels.md):

   ```sh
   gh label create "host(<host>)" --color 5319E7 --description "Specific to the <host> host or its runtime contract."
   ```

2. Add `<host>` to the fleet inventories in `docs/ONBOARDING.md`, `docs/architecture/01-pattern-overview.md`, `docs/architecture/04-home-manager.md`, and `docs/architecture/host-file-inventory.md`.
   Add host-specific module exports to `docs/architecture/03-nixos-modules.md` only when the host introduces them.
   If the host adds documentation pages, add its directory to `docs/architecture/README.md` and its pages to `docs/index.md`.

3. No workflow edits are needed. `.github/workflows/check.yml` and `.github/workflows/update-flake.yml` derive the host list from `nix eval --accept-flake-config --json "path:.#nixosConfigurations" --apply builtins.attrNames`, so the new host is covered without touching either. `check.yml` only forces each host's `system.build.toplevel.drvPath` through `nix eval`, not `nix build --dry-run`, because Lix forces read-only store mode for `--dry-run` and that breaks eval-time store writes on the fresh runner; a compliance run proves the host evaluates to a derivation, not that its closure builds or substitutes. `update-flake.yml` is what builds each host closure, one at a time with `nix store gc` between hosts to respect runner disk.

Verification: `gh label list --search 'host('` includes `host(<host>)`, and `rg -l -w <host> docs/` includes every applicable page named above.

Install the age identity, provision secrets, pin the SSH host key, and hand off the primary role in [Host secrets and handoff](host-onboarding-secrets.md).
