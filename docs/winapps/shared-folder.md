# Windows shared folder

Virtiofs exposes the host transfer directory as a Windows drive across console and RDP sessions.
The host path comes from `modules/hosts/common/windows-guest.nix`; Home Manager creates it during activation.
The file server runs as the host owner, so Windows cannot create files owned by another host account.
Every Windows account that can access the drive can modify its contents.
`modules/hosts/common/windows-guest-filesystem.nix` provisions WinFsp Core, the signed VirtIO filesystem driver, and the Windows service through the QEMU guest agent.
Windows needs no internet access for this setup; the host sends pinned payloads through the guest agent.

## Enable the Windows drive

Precondition: the [guest tools](provisioning.md#install-guest-tools) are installed, and Windows has an unused drive letter `T:`.

1. Apply the host configuration from the repository root with `./build.sh`.
   Shut Windows down fully, then start the guest so the virtiofs device and shared memory backing take effect.

2. On the host, inspect the provisioning result:

   ```sh
   systemctl status windows-guest-filesystem.timer
   journalctl -u windows-guest-filesystem.service -n 50 --no-pager
   ```

   The timer defers while Windows is off and reconciles once the agent responds.
   A ready result confirms automatic service startup and the mounted drive.

3. If installation reports a required restart, restart Windows when convenient.
   Provisioning waits for that restart and never initiates one.
   A drive-letter conflict or installer failure leaves a diagnostic in the service journal.

   To retry immediately after resolving a failure, run on the host:

   ```sh
   sudo systemctl start windows-guest-filesystem.service
   ```

The declaration removes the Windows `Owner` override so ownership comes from the share root inside the file server's user namespace.

Verification: `Get-Volume -DriveLetter T` reports the transfer volume in both the virt-manager console and a `winapps windows` session.
Shut Windows down and start it again; the drive must mount without launching Outlook.

## Verify access from both sides

Precondition: the Windows drive is mounted.

1. In guest PowerShell, write a file:

   ```powershell
   Set-Content T:\ownership-check.txt 'created in Windows'
   ```

2. On the host, check ownership and append data:

   ```sh
   stat -c '%U:%G %a %n' ~/Documents/Outlook-Transfer/ownership-check.txt
   printf '%s\n' 'appended on host' >> ~/Documents/Outlook-Transfer/ownership-check.txt
   ```

3. In guest PowerShell, read the result:

   ```powershell
   Get-Content T:\ownership-check.txt
   ```

Verification: the file belongs to the host owner and primary group, and Windows reads both lines.

## Transfer constraints

Use the drive for exchanging files; keep Outlook's active mailbox data on the guest disk.
Refresh Explorer after changing files on the host, and avoid filenames that differ only by case.
Host files that the owner cannot access remain inaccessible.
Changing the Windows `Owner` setting does not grant another host identity and can cause writes to fail.
The provisioning service restores its declared service settings and removes that override on its next run.

Sources: [VirtIO filesystem setup](https://github.com/virtio-win/kvm-guest-drivers-windows/wiki/Virtiofs:-Shared-file-system), [driver registry handling](https://github.com/virtio-win/kvm-guest-drivers-windows/blob/mm322/viofs/svc/virtiofs.cpp), [guest-agent protocol](https://www.qemu.org/docs/master/interop/qemu-ga-ref.html).
