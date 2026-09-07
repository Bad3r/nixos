# Songbird runbook

Windows procedures are in [songbird-runbook-windows.md](songbird-runbook-windows.md).

## Reinstall NixOS on disk A

Precondition: a NixOS installer image is booted with network access, and the shell is root (`sudo -i`).

1. Partition, encrypt, and format disk A, giving both `luksFormat` prompts one passphrase so the initrd opens every volume from a single prompt:

   ```sh
   DISK=/dev/disk/by-id/nvme-WD_BLACK_SN8100_4000GB_252415800489
   sgdisk --zap-all "$DISK"
   sgdisk -n1:0:+1GiB  -t1:ef00 -c1:ESP        "$DISK"
   sgdisk -n2:0:-51GiB -t2:8309 -c2:cryptroot  "$DISK"
   sgdisk -n3:0:0      -t3:8309 -c3:cryptswap  "$DISK"
   udevadm settle
   cryptsetup luksFormat --type luks2 "$DISK-part2"
   cryptsetup luksFormat --type luks2 "$DISK-part3"
   cryptsetup open "$DISK-part2" cryptroot
   cryptsetup open "$DISK-part3" cryptswap
   mkfs.vfat -F32 -n ESP "$DISK-part1"
   mkfs.ext4 -L root /dev/mapper/cryptroot
   mkswap -L swap /dev/mapper/cryptswap
   ```

2. Install NixOS from the live image onto the new partitions with the installer's stock configuration.

3. Re-harvest the partition identifiers:

   ```sh
   blkid "$DISK-part1" "$DISK-part2" "$DISK-part3"
   ```

   The vfat UUID goes to `fileSystems."/boot".device` and the two `crypto_LUKS` UUIDs to `boot.initrd.luks.devices.cryptroot.device` and `.cryptswap.device` in `modules/songbird/hardware-config.nix`.
   Root and swap mount through `/dev/mapper`, so the ext4 and swap UUIDs inside the containers are not used.

Verification: `lsblk -o NAME,FSTYPE,UUID` lists `cryptroot` and `cryptswap` mapped on disk A.

## First switch after a reinstall

Precondition: disk A boots the installer's stock configuration, with no checkout on it.

1. Clone the repository without `--recurse-submodules`:

   ```sh
   nix --extra-experimental-features "nix-command flakes" shell nixpkgs#git -c git clone https://github.com/Bad3r/nixos ~/nixos
   ```

   `secrets/` stays uninitialized until the age identity exists; every `sops` declaration guards on the encrypted file's presence, so a secretless checkout still evaluates and activates.
   The tree stays untouched until the switch below, since `build.sh` exits on an uncommitted change and the stock system carries no git identity to commit with.

2. Build and stage the first generation:

   ```sh
   cd ~/nixos
   nix --extra-experimental-features "nix-command flakes" shell nixpkgs#git nixpkgs#nh -c ./build.sh -t songbird --boot
   ```

   `nix shell nixpkgs#git` supplies `git`, since the stock system ships none and both the Nix git fetcher and the secrets guard shell out to it.
   The stock configuration enables no experimental features, so the flag carries `nix shell` until `modules/base/nix-settings.nix` lands; `build.sh` bootstraps its own Nix commands.
   `-t songbird` is required because `build.sh` defaults the target to `$(hostname)`, still `nixos` under the stock configuration.
   `--boot` installs the generation for the next reboot instead of switching the running session live, and Home Manager moves any pre-existing `$HOME` file it manages aside with the `.hm.bk` extension rather than failing activation.

Verification: reboot; the initrd asks for the root passphrase once, and `cryptroot`, `cryptswap`, and `data` all open from that single prompt.
A `data` volume keyed to an older passphrase prompts again until the key-slot procedure below adds the new one.

## Install the age identity and secrets

Precondition: songbird is running this repository's configuration, with `secrets/` still uninitialized.

1. Copy the age private key from the password manager to `/var/lib/sops-nix/key.txt` (root, mode 0600) and `~/.config/sops/age/keys.txt`.
   See [SOPS usage](../sops/README.md), Host Preparation, for the exact key handling.

2. Initialize the secrets submodule now that the age identity exists:

   ```sh
   git submodule update --init --recursive
   ```

3. Replace the stale host key pin in `modules/songbird/ssh.nix` and `fleetHostKeys` with `cat /etc/ssh/ssh_host_ed25519_key.pub`, per [Pin the SSH host key](../guides/host-onboarding-secrets.md#pin-the-ssh-host-key).
   Replace the host id in `modules/songbird/host-id.nix` with `head -c 8 /etc/machine-id`, which the first boot generated, then commit both; `build.sh` refuses an uncommitted tree.

4. Rebuild with the secrets submodule present:

   ```sh
   ./build.sh
   ```

Verification:

```sh
ls /run/secrets
systemctl status r2-runtime-paths.service
```

`ls /run/secrets` lists the host secrets, `r2-runtime-paths.service` shows the `/data` tree in place, and `modules/songbird/ssh.nix` carries the key `/etc/ssh/ssh_host_ed25519_key.pub` holds.

## Give the /data volume the root passphrase key slot

Precondition: the `data` LUKS container sits at the device path recorded in `boot.initrd.luks.devices.data.device` in `modules/songbird/hardware-config.nix`.
A volume created from scratch also needs the XFS filesystem `data.mount` expects, `sudo mkfs.xfs -L data /dev/mapper/data` with the container open; never run that on a volume whose contents stay.

1. Add the root passphrase as an extra key slot:

   ```sh
   sudo cryptsetup luksAddKey <data-device-path>
   ```

   Authenticate with the volume's own passphrase, then enter the same passphrase used for `cryptroot` and `cryptswap` as the new key.

Verification: reboot; the initrd's single passphrase prompt opens `cryptroot`, `cryptswap`, and `data` with no second prompt, and `findmnt /data` shows the xfs mount.

## Validate a host change

Precondition: the change sits in a linked worktree.

1. Format and check the flake:

   ```sh
   nix run path:.#treefmt -- .
   nix flake check path:. --accept-flake-config --no-build --offline
   ```

2. Build the host closure:

   ```sh
   nix build "path:.#nixosConfigurations.songbird.config.system.build.toplevel"
   ```

3. Switch on songbird:

   ```sh
   ./build.sh
   ```

4. Score the generation:

   ```sh
   nix run path:.#generation-manager -- score
   ```

Verification:

- `lsblk -o NAME,FSTYPE,UUID` shows `cryptroot`, `cryptswap`, and `data` mapped.
- `nvidia-smi` reports the GPU on the open kernel module.
- `ip -br link` shows `eth0`, `eth1`, and `wlan0`.
- `powerprofilesctl get` reports `performance`.
- `systemctl hibernate` round-trips, and `/portal` remounts on resume.
