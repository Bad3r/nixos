# Host secrets and handoff

Continues [Host Onboarding Runbook](host-onboarding.md) after the new host boots: age identity, secrets, backup manifest, SSH host key pin, and primary handoff.

## Install the age identity

Precondition: the host boots this repository's configuration, with `secrets/` uninitialized.

1. Install the canonical age identity on the machine, following Host Preparation in [SOPS usage](../sops/README.md).
   The repository uses one recipient for every host, so this step never edits `.sops.yaml` and never runs `sops updatekeys`.

2. Flip the flag in `modules/<host>/policy.nix`:

   ```nix
   sopsRuntimeReady = true;
   ```

Verification: the public key printed by Host Preparation's `age-keygen -y` step matches `host_pub_key` in `.sops.yaml`.

## Provision host secrets

Precondition: the age identity is installed, with `sopsRuntimeReady = true` and `gh` logged in, since Home Manager's `gh` module makes `gh auth git-credential` git's helper for github.com and the private submodule fetches through it.

1. Initialize the secrets submodule now that the identity exists:

   ```sh
   git submodule update --init --recursive
   ```

2. Add `secrets/<host>.yaml` only if the host needs secrets no existing file already carries:

   ```sh
   sops secrets/<host>.yaml
   ```

   The catch-all rule in `.sops.yaml` matches any `secrets/*` path, so a new host-scoped file needs no policy edit.

3. Guard every new `sops.secrets` declaration with `builtins.pathExists` on the encrypted file, so a checkout without the submodule still evaluates.

4. Commit the new file inside the submodule (`git -C secrets add <host>.yaml && git -C secrets commit`), then push it with `git -C secrets push origin HEAD:main`, before opening a PR or running `nix flake check` elsewhere.
   `modules/git/git.nix` sets `signing.signByDefault` with 1Password's `op-ssh-sign` in the owner's global git config, so this submodule commit is signed too; sign in to 1Password on this host first, or make it with `git -C secrets -c commit.gpgsign=false commit`.
   `git submodule update --init` leaves `secrets/` on a detached HEAD, so a bare `git -C secrets push` exits with `You are not currently on a branch`; the explicit refspec is also what the verification below looks for.
   Without that push the superproject still records the new gitlink in step 5, but no remote carries that submodule revision.
   `.gitmodules` gives `secrets` an absolute `https://github.com/Bad3r/secrets.git` URL, so the `git+file` reference that step 5 resolves fetches the submodule from that remote.
   That fetch fails with `Cannot find Git revision` on this host too, not only elsewhere, and the verification below returns empty.

5. On the new host, remove any temporary `security.repoSecrets.enable = false;` bootstrap override, then commit that removal with the `sopsRuntimeReady` flip, the new `sops.secrets` declarations, and the moved `secrets` gitlink.
   Both age identity copies from the first section must exist before removing the override; the common `lib.mkDefault true` then restores the repo-managed declarations for this secret-bearing switch:

   ```sh
   ./build.sh --skip-hooks --host <host>
   ```

   `--skip-hooks` keeps the same devshell build off this switch that the boot command in [Host Onboarding Runbook](host-onboarding.md) avoided; the ordinary `./build.sh` a reader runs afterward for routine changes is what exercises those hooks on this host for the first time.
   `build.sh` hands the name to `nh os switch -H <host>`, which activates on the machine it runs on; from any other machine this step switches that machine into `<host>`'s configuration.
   A linked worktree takes the `path:` reference on its own; a primary checkout resolves the bare `git+file` reference and keeps `self.rev`, since step 1 already fetched the private submodule through the `gh` credential helper and this step's commit leaves the tree clean.

6. Confirm every source path in the shared `secrets/duplicati-config.json` manifest exists on this host.
   `sopsRuntimeReady = true` enables `services.duplicati-r2` against that one manifest, and its generator checks that a target names a path, not that the path exists here.

Verification: `git -C secrets fetch origin && git -C secrets branch -r --contains HEAD` lists `origin/main`.
Empty output means the commit is unpushed, and evaluation elsewhere then fails with `Cannot find Git revision`.
`ls /run/secrets` lists the host secrets, and `systemctl list-timers 'duplicati-r2-backup-*'` lists one timer per enabled target.

## Pin the SSH host key

Precondition: the host has booted, so `/etc/ssh/ssh_host_ed25519_key.pub` exists on it.

1. Add `services.openssh.publicKey` beside the existing enable choice in `modules/<host>/ssh.nix`, and add the same key to `fleetHostKeys` in `modules/hosts/common/ssh-known-hosts.nix`, in one commit:

   ```nix
   <host> = "ssh-ed25519 AAAA...";
   ```

   `modules/configurations/nixos.nix` throws when either side is set without the other.

2. Switch every other `shareCommon` host so it picks up the new pin.
   `/etc/ssh/ssh_known_hosts` is rendered at build time from `fleetHostKeys`, so a host that has not rebuilt still carries the old table.
   For a new host that leaves the first connection trust-on-first-use; for a replaced key it fails with `REMOTE HOST IDENTIFICATION HAS CHANGED`.

Before the direct `path:.` check, inventory ignored paths and require the shared secrets guard to pass; benign inventory output may appear.

```sh
git status --porcelain --ignored=matching
git submodule foreach --recursive 'git status --porcelain --ignored=matching'
bash -c 'source scripts/lib/secrets-guard.sh && secrets_guard_enforce "$PWD" "path:$PWD"' &&
  nix flake check path:. --accept-flake-config --no-build --offline
```

Verification: the guarded flake check passes the check in `modules/configurations/nixos.nix` that throws on a `publicKey` with no matching `fleetHostKeys` pin. If SSH is enabled, `ssh -o StrictHostKeyChecking=yes <host>` from another fleet host connects with no prompt; if disabled, `systemctl is-active sshd.service` on the new host reports `inactive` after the switch.

## Hand off the primary role

Precondition: this host replaces the current primary fleet endpoint.

1. Remove `primary = true` from the outgoing primary host. If that host is being retired, remove its `tailnetIp` too. On this host, run `tailscale ip -4`, then set `primary = true` with that address as this host's `tailnetIp`.

   `programs.tailscale.extended.sshHostName` in `modules/apps/tailscale.nix` defaults to the primary host's own `tailnetIp`; copying the outgoing host's value leaves the fleet alias pointed at the old endpoint.
   Evaluation names and rejects duplicate primaries or a primary with a missing, null, empty, or whitespace-only `tailnetIp`, but it cannot prove which host owns an otherwise valid address.

2. Switch every host that carries the fleet SSH config. With the current common baseline, this is every `shareCommon` host, including the incoming and outgoing primary. `modules/networking/ssh-hosts.nix` renders `~/.ssh/hosts/tailscale` at build time, so an unswitched host retains the outgoing primary's address.

Verification: on each switched host, `ssh -G tailscale | awk '$1 == "hostname" { print $2; exit }'` prints the new primary's tailnet address.
