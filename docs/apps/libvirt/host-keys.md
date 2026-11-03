# Guest SSH access

The host's SSH client trusts each declared guest's host key without a first-connection prompt, and logs in with a key that needs no 1Password unlock.
`modules/workloads/vms/host-keys.nix` covers every present guest that has a guest agent and an interface.

## How a key is recorded

A libvirt hook queues `workloads-host-key@<name>.service` when the guest starts or libvirtd reconnects to it, and stops the unit when the guest stops.
The unit reads the guest's ED25519 public key through the QEMU guest agent, which reaches the guest without the network, so no address on the bridge can answer for it.
It waits until the key exists: a Windows guest has one only after `firstlogon.ps1` installs OpenSSH.

The key is stored in `/var/lib/workloads/host-keys/<name>.key`, and `/var/lib/workloads/ssh_known_hosts` is rebuilt from the stored keys of declared guests.
A reinstalled guest's new key replaces the old one at its next start.

`workloads-host-keys.service` rebuilds the file at boot and at every switch that changes the declared guests.
It drops the keys of undeclared guests and queues a capture for every running guest.

## How SSH uses the file

`/etc/ssh/ssh_config` gets a `Host` block for each guest's `<name>`, `<name>.vm`, and addresses, which adds the file as a global known-hosts file.
Other hosts never consult it, so a guest can vouch only for its own names.

A guest controls what its agent returns, so the unit accepts only one well-formed ED25519 key and builds each line from the declared hostnames.

## The guest login key

`secrets/workloads-ssh.yaml` holds a dedicated client key, and its public half is `workloadsSshPublicKey` in `modules/meta/_owner-profile.nix`.
NixOS guests authorize it for root and the owner, and a Windows guest gets it through its `authorizedKeys`, which provisioning writes at each start.

On Songbird, Home Manager decrypts the key to `~/.ssh/keys/workloads-guest`, and `modules/hosts/songbird/ssh-workloads.nix` writes `~/.ssh/hosts/workloads`.
`~/.ssh/config` includes that file ahead of its `Host *` block.
The guests' names and addresses use the key with `IdentityAgent none`; every other host keeps the 1Password agent.
Without the secret file, the host warns at evaluation and guests keep the 1Password agent.

## Verify

```sh
ssh-keygen -F <name>.vm -f /var/lib/workloads/ssh_known_hosts
ssh -o BatchMode=yes <user>@<name>.vm true
```

The first command prints the guest's line; the second connects without a host-key prompt.

## ssh reports no host key for a guest

Cause: the guest has not started since the host gained the unit, its agent is not answering, or its SSH server has not generated a key yet.

```sh
systemctl status workloads-host-key@<name>.service
journalctl -u workloads-host-key@<name>.service -b
```

The journal names the file the unit waits for and the agent's error.
A unit that stays activating with `waiting for` lines has no key to read yet; it records the key once the guest creates it.

Fix: start the guest, or restart the unit once its agent runs:

```sh
sudo systemctl restart workloads-host-key@<name>.service
```

## A guest refuses the login key

Cause: the guest still runs a configuration from before the key was authorized.
A Windows guest picks the key up at its next start; a NixOS guest needs a deploy, which itself logs in over SSH.

Fix: deploy the NixOS guest once through the 1Password agent, since `-o` overrides the config file.
From the repository root on the host, with `path:.#` in a linked worktree:

```sh
NIX_SSHOPTS="-o IdentityAgent=~/.1password/agent.sock" nixos-rebuild switch --flake .#<name> --target-host root@<name>
```

For a Windows guest, restart it from Windows or with `virsh -c qemu:///system reboot <name>`.
