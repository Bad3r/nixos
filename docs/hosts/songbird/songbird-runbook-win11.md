# Songbird runbook: win11 guest

The pipeline behind these procedures is in [Windows guests](../../apps/libvirt/windows.md), and ad-hoc guests are in [songbird-runbook-vms.md](songbird-runbook-vms.md).

## Create the win11 secret

Precondition: `secrets/workloads.yaml` does not exist; the win11 guest, its media, and its secret stay out of every generation until it does.

1. From `~/nixos`, create the encrypted file with the account password under the key `win11_password`:

   ```sh
   sops secrets/workloads.yaml
   ```

2. Commit and push it inside `secrets/` on its `main`, then commit the new gitlink in `~/nixos` as `chore: update secrets hash`.

Verification: `yq 'keys' secrets/workloads.yaml` lists `win11_password` and `sops`.

## Install the win11 guest

Precondition: `/data` is unlocked and `secrets/workloads.yaml` exists; the pipeline is described in [Windows guests](../../apps/libvirt/windows.md).

1. Put the Windows 11 Business ISO at `installIso` from `win11` in `modules/hosts/songbird/policy.nix`, then check that its hash matches `installIsoSha256`:

   ```sh
   nix eval --json .#lib.nixos.hosts.songbird.win11 --apply 'w: { inherit (w) installIso installIsoSha256; }'
   sha256sum /data/Misc/windows/en-us_windows_11_business.iso
   ```

2. As the owner in `~/nixos`, build the virtio-win and seed out-links:

   ```sh
   nix build .#legacyPackages.x86_64-linux.workloads.virtio-win --out-link /var/lib/workloads/images/virtio-win
   nix build .#legacyPackages.x86_64-linux.workloads.win11-seed --out-link /var/lib/workloads/images/win11-seed
   ```

3. Switch through [Validate a host change](songbird-runbook.md#validate-a-host-change).
   A missing ISO or out-link only leaves the guest undefined with a warning; after supplying it, rerun staging and the definition:

   ```sh
   sudo systemctl restart workloads-vm-media.service workloads-vm-guest-win11.service
   journalctl -u workloads-vm-media.service -u workloads-vm-guest-win11.service -b -p warning
   ```

4. Start the guest, which starts provisioning, and watch it:

   ```sh
   virsh -c qemu:///system start win11
   virt-viewer -c qemu:///system win11 &
   journalctl -fu workloads-provision@win11.service
   ```

   Setup, the first logon, and the provisioning steps run without input until the journal logs `guest 'win11' is provisioned`.

Verification, as the owner:

```sh
ssh "vx@$(nix eval --raw .#nixosConfigurations.songbird.config.workloads.guests.win11.address.lan)" 'cscript //nologo C:\Windows\System32\slmgr.vbs /xpr'
```

SSH logs in with the owner's key, `slmgr /xpr` reports activation only when a product key is declared, and Remmina reaches Remote Desktop at that address with the sops password.

## Activate win11 with a product key

Precondition: the win11 guest is installed and running.

1. Add the key under `win11_product_key` with `sops secrets/workloads.yaml`, and push it as in the install procedure.

2. In `modules/hosts/songbird/workloads.nix`, declare `sops.secrets."workloads/win11/product-key"` like the password entry with `key = "win11_product_key"`, and set `windows.productKeySecret` to that name.

3. Switch, then rerun the steps:

   ```sh
   sudo systemctl restart workloads-provision@win11.service
   ```

Verification: `journalctl -u workloads-provision@win11.service -b` logs `product-key: applied`.

## Install Office on win11

Precondition: the win11 guest is installed and running, `/data` is unlocked, and the `OfficeSetup.exe` from the Microsoft account's Office page sits in `/data/Misc/windows/`.

1. Print the installer's hash:

   ```sh
   sha256sum /data/Misc/windows/OfficeSetup.exe
   ```

2. In `win11` in `modules/hosts/songbird/policy.nix`, set `officeInstaller`:

   ```nix
   officeInstaller = {
     source = "/data/Misc/windows/OfficeSetup.exe";
     sha256 = "<hash from step 1>";
   };
   ```

3. Switch, then rerun the steps and watch the installation:

   ```sh
   sudo systemctl restart workloads-provision@win11.service
   journalctl -fu workloads-provision@win11.service
   ```

4. Open Word in the guest and sign in with the account that owns the subscription.

Verification: the journal logs `office: applied`, and Word reports the subscription under File > Account.
Setting `officeInstaller` back to `null` keeps Office installed; the step then stops reinstalling it.

## Drop the win11 installation media

Precondition: the guest is provisioned, and the golden copy below is taken if one is wanted from the fresh install.

1. Remove the `install` block of win11 from `modules/hosts/songbird/workloads.nix`; the ISO media, the virtio-win image, and the seed image go with it.

2. Switch, then shut the guest down and start it, so the CD-ROMs leave its running definition, and remove the out-links so the store can collect the ISOs:

   ```sh
   rm /var/lib/workloads/images/virtio-win /var/lib/workloads/images/win11-seed
   ```

Verification: `ls /var/lib/workloads/media/` omits `win11-iso`, and `virsh -r -c qemu:///system domblklist win11` lists only the disk.

## Take the win11 golden copy

Precondition: songbird passed a full memtest86+ run in person, and win11 is shut off.

1. Start the copy as the owner, as in [Take a golden copy](../../apps/libvirt/windows.md#take-a-golden-copy):

   ```sh
   sudo systemctl start workloads-golden@win11.service
   ```

Verification: `journalctl -u workloads-golden@win11.service -b` ends with `copied guest 'win11'`.
