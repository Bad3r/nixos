# Guest SSH host keys

The host's SSH client trusts each declared guest's host key without a first-connection prompt.
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
