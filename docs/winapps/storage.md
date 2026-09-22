# WinApps guest storage

Read the [rules that prevent data loss](README.md#rules-that-prevent-data-loss) before copying over or deleting guest state.
Commands run on the host unless a step names the guest.

## Record a baseline

Precondition: the guest is shut off, and the target directory leaves `/` with 20 GiB free after the copy.

1. Read the state locations:

   ```sh
   disk=$(virsh --connect qemu:///system vol-path --pool winapps RDPWindows.qcow2)
   nvram=$(virsh --connect qemu:///system dumpxml RDPWindows --xpath '//os/nvram/text()')
   uuid=$(virsh --connect qemu:///system domuuid RDPWindows)
   ```

2. Compare the allocated disk size with the free space:

   ```sh
   sudo du -h "$disk"
   df -h /
   ```

3. Copy the disk, the UEFI variable store, the TPM state, and the definition together:

   ```sh
   dest=<baseline-directory>
   sudo mkdir -p "$dest"
   sudo cp -a --sparse=always "$disk" "$dest/RDPWindows.qcow2"
   sudo cp -a "$nvram" "$dest/"
   sudo cp -a "/var/lib/libvirt/swtpm/$uuid" "$dest/swtpm"
   virsh --connect qemu:///system dumpxml --inactive RDPWindows | sudo tee "$dest/RDPWindows.xml" >/dev/null
   ```

   When space is short, write the disk with `sudo qemu-img convert -c -O qcow2 "$disk" "$dest/RDPWindows.qcow2"` instead, which compresses it.

Verification: `sudo qemu-img check "$dest/RDPWindows.qcow2"` reports no errors, and `$dest` holds the four parts.

## Restore the baseline

Precondition: the guest is shut off, its present disk and UEFI variables are expendable, and `dest`, `disk`, `nvram`, and `uuid` are set as in the baseline procedure.

1. Write the baseline over the guest state, setting the present TPM state aside:

   ```sh
   sudo qemu-img convert -O qcow2 "$dest/RDPWindows.qcow2" "${disk:?}"
   sudo cp -a "$dest/$(basename "$nvram")" "${nvram:?}"
   sudo mv "/var/lib/libvirt/swtpm/${uuid:?}" "/var/lib/libvirt/swtpm/$uuid.replaced"
   sudo cp -a "$dest/swtpm" "/var/lib/libvirt/swtpm/$uuid"
   ```

2. Start the guest:

   ```sh
   virsh --connect qemu:///system start RDPWindows
   ```

3. Delete the `.replaced` TPM directory once the guest boots.

Verification: Windows boots to the sign-in screen without a BitLocker or Secure Boot prompt.

## Grow the disk

Precondition: the guest is shut off and a baseline exists.

1. Resize the volume; NixVirt never resizes an existing volume:

   ```sh
   virsh --connect qemu:///system vol-resize --pool winapps RDPWindows.qcow2 <new-capacity>G
   ```

2. Set the same capacity on the volume in `modules/hosts/common/windows-guest.nix`, so the declaration matches the disk.

3. Start the guest, and in an elevated prompt remove the recovery partition that sits behind `C:`:

   ```powershell
   reagentc /disable
   diskpart
   ```

   In `diskpart`, select the disk, select the recovery partition, and run `delete partition override`.

4. Extend `C:` in Disk Management, then run `reagentc /enable`.

Verification: `virsh --connect qemu:///system vol-info --pool winapps RDPWindows.qcow2` reports the new capacity, and Windows shows the larger `C:` volume.
