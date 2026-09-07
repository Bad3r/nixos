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

4. Push the secrets submodule commit before opening a PR or running `nix flake check` elsewhere.

5. On the new host, commit the `sopsRuntimeReady` flip, the new `sops.secrets` declarations, and the moved `secrets` gitlink, then switch so sops-nix installs the secrets:

   ```sh
   ./build.sh --host <host>
   ```

   `build.sh` hands the name to `nh os switch -H <host>`, which activates on the machine it runs on; from any other machine this step switches that machine into `<host>`'s configuration.
   A linked worktree takes the `path:` reference on its own; a primary checkout resolves the bare `git+file` reference and keeps `self.rev`, since step 1 already fetched the private submodule through the `gh` credential helper and this step's commit leaves the tree clean.

6. Confirm every source path in the shared `secrets/duplicati-config.json` manifest exists on this host.
   `sopsRuntimeReady = true` enables `services.duplicati-r2` against that one manifest, and its generator checks that a target names a path, not that the path exists here.

Verification: `git -C secrets fetch origin && git -C secrets branch -r --contains HEAD` lists `origin/main`.
Empty output means the commit is unpushed, and evaluation elsewhere then fails with `Cannot find Git revision`.
`ls /run/secrets` lists the host secrets, and `systemctl list-timers 'duplicati-r2-backup-*'` lists one timer per enabled target.

## Pin the SSH host key

Precondition: the host has booted, so `/etc/ssh/ssh_host_ed25519_key.pub` exists on it.

1. Set `services.openssh.publicKey` in `modules/<host>/ssh.nix` and add the same key to `fleetHostKeys` in `modules/hosts/common/ssh-known-hosts.nix`, in one commit:

   ```nix
   <host> = "ssh-ed25519 AAAA...";
   ```

   `modules/configurations/nixos.nix` throws when either side is set without the other.

2. Switch every other `shareCommon` host so it picks up the new pin.
   `/etc/ssh/ssh_known_hosts` is rendered at build time from `fleetHostKeys`, so a host that has not rebuilt still carries the old table.
   For a new host that leaves the first connection trust-on-first-use; for a replaced key it fails with `REMOTE HOST IDENTIFICATION HAS CHANGED`.

Verification: `nix flake check path:. --accept-flake-config --no-build --offline` passes the check in `modules/configurations/nixos.nix` that throws on a `publicKey` with no matching `fleetHostKeys` pin, and `ssh -o StrictHostKeyChecking=yes <host>` from another fleet host connects with no prompt.

## Hand off the primary role

Precondition: this host replaces the current primary fleet endpoint.

1. Move `primary = true` and `tailnetIp` from the outgoing primary host's `policy.nix` to this host's `policy.nix`.

   `programs.tailscale.extended.sshHostName` in `modules/apps/tailscale.nix` defaults to the `tailnetIp` of whichever registry host is marked `primary`, so moving those two keys is the entire handoff.

Verification: on a machine with the fleet SSH config, `ssh tailscale` resolves to this host's tailnet address.
