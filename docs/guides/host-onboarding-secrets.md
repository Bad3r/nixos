# Host secrets and handoff

Continues [Host Onboarding Runbook](host-onboarding.md) after the new host boots: age identity, secrets, SSH host key pin, and primary handoff.

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

Precondition: the age identity is installed, with `sopsRuntimeReady = true`.

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

Verification: `git -C secrets status` reports no unpushed commits; an unpushed commit otherwise fails evaluation with `Cannot find Git revision`.

## Pin the SSH host key

Precondition: `modules/<host>/ssh.nix` sets `services.openssh.publicKey`.

1. Add the same key to `fleetHostKeys` in `modules/hosts/common/ssh-known-hosts.nix`:

   ```nix
   <host> = "ssh-ed25519 AAAA...";
   ```

   Every `shareCommon` host, including this one, then carries every other fleet host's key in `/etc/ssh/ssh_known_hosts`, so the first connection between fleet hosts is never trust-on-first-use.

Verification: `nix flake check path:. --accept-flake-config --no-build --offline` builds the check in `modules/configurations/nixos.nix` that throws when a host's `publicKey` has no matching `fleetHostKeys` pin.

## Hand off the primary role

Precondition: this host replaces the current primary fleet endpoint.

1. Move `primary = true` and `tailnetIp` from the outgoing primary host's `policy.nix` to this host's `policy.nix`.

   `programs.tailscale.extended.sshHostName` in `modules/apps/tailscale.nix` defaults to the `tailnetIp` of whichever registry host is marked `primary`, so moving those two keys is the entire handoff.

Verification: on a machine with the fleet SSH config, `ssh tailscale` resolves to this host's tailnet address.
