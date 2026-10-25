# NixOS guests

A NixOS guest is a flake configuration under `modules/workloads/guests/<name>/` that a host runs as a [declared guest](guests.md).
Its first disk is a copy of the configuration's `qemu-efi` image.
A declared guest with an interface gets a [workload name](../../networking/workload-names.md), so the host reaches it as `<name>`, which the `fleetHostKeys` pin matches.
Every later change reaches the running guest through `nixos-rebuild` over SSH, never through a new image.

## Guest base

`workloads-guest-base` in `modules/workloads/vms/guest-base.nix` carries what every NixOS guest shares:

- the disk layout of the `qemu-efi` image, so a deployed system boots the disk the image seeded;
- the QEMU guest agent and a serial console;
- sshd with the owner's keys for root and the owner;
- fstab entries for the guest's [shares](shares.md).

A guest has no password, so a console login needs one set with `passwd` over SSH first.

## Add a guest

1. Create `modules/workloads/guests/<name>/configuration.nix`:

   ```nix
   { config, ... }:
   {
     configurations.nixos.<name>.module = {
       imports = [ config.flake.nixosModules."workloads-guest-base" ];
       workloads.guest.shares =
         config.flake.nixosConfigurations.<host>.config.workloads.guests.<name>.mounts;
       system.stateVersion = "<release>";
     };

     perSystem.workloads.artifacts.<name> =
       config.flake.nixosConfigurations.<name>.config.system.build.images.qemu-efi;
   }
   ```

2. Register it in `modules/hosts/common/registry.nix` with `<name>.shareCommon = false;`, so it skips the hosts-common baseline.

3. Declare the image and the guest in `modules/hosts/<host>/workloads.nix`, where `image` is the same `qemu-efi` attribute:

   ```nix
   configurations.nixos.<host>.module.workloads = {
     images.<name> = {
       expected = "${image}/${image.passthru.filePath}";
     };
     guests.<name> = {
       kind = "nixos";
       disks.root = {
         size = <GiB>;
         seed = "<name>";
       };
     };
   };
   ```

The rest of the guest declaration follows [Declare a guest](guests.md#declare-a-guest).
`expected` is stored without string context, so the image never enters the host closure.
CI builds and checks the guest's system like a host's, and never builds its image.

## Seed and boot a guest

Precondition: the guest is declared, and the host runs a generation with the libvirt app.
A switch before the image exists succeeds, and a guest that libvirt has not defined yet stays undefined until step 2.

1. Build the image as the owner, from the repository root on the host, with `path:.#` in a linked worktree:

   ```sh
   nix build .#legacyPackages.x86_64-linux.workloads.<name> --out-link /var/lib/workloads/images/<name>
   ```

2. Define the guest: switch the host, or restart its unit when the running generation already declares it:

   ```sh
   sudo systemctl restart workloads-vm-guest-<name>.service
   ```

   The unit copies the image into the guest directory, grows it to the declared size, and defines the guest.

3. Start the guest and watch it boot on the serial console; `Ctrl+]` detaches:

   ```sh
   virsh -c qemu:///system start <name>
   virsh -c qemu:///system console <name>
   ```

4. Log in:

   ```sh
   ssh root@<name>
   ```

The root file system grows to the full disk at first boot.
The image is read only when the disk is created, so the out-link can go once the guest has booted.
A stale out-link never touches an existing disk.

Verification: `ssh root@<name> systemctl is-system-running` prints `running`.

## Pin the host key

Precondition: the guest has booted once and generated its SSH host key.

1. Read the key from the host; the bridge is local to the host, so the scan reaches the guest itself:

   ```sh
   ssh-keyscan -t ed25519 <name>
   ```

2. Set the key as `services.openssh.publicKey` in the guest configuration, and add it under the guest name to `fleetHostKeys` in `modules/hosts/common/ssh-known-hosts.nix`.

3. Switch the host, then deploy the guest.

Verification: `nix flake check` passes `configurations/nixos/<name>`, which fails when the two keys differ.

## Deploy a configuration change

Precondition: the guest runs and the owner's SSH key logs in as root.

From the repository root on the host:

```sh
nixos-rebuild switch --flake .#<name> --target-host root@<name>
```

The host builds the system and copies it to the guest, which never builds.
`build.sh` refuses a guest name, since it activates the configuration on the machine it runs on.

Verification: `ssh root@<name> readlink /run/current-system` prints the path that `nix eval --raw .#nixosConfigurations.<name>.config.system.build.toplevel` prints.

## A declared guest is missing from virsh list --all

Cause: libvirt has not defined the guest, its disk does not exist yet, and the image out-link is missing or points at an older build.
The unit then succeeds without defining the guest and logs a warning that names the out-link and the `nix build` command:

```sh
journalctl -u workloads-vm-guest-<name>.service -b -p warning
```

Fix: run the `nix build` command from the warning as the owner in the repository root, with `path:.#` in a linked worktree, then `sudo systemctl restart workloads-vm-guest-<name>.service`.
