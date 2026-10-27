# Songbird: persistent win11 VM quick start

Use the installed `win11` guest from a terminal on Songbird as `vx`.
Changes inside Windows and files in its drop folder persist across shutdowns.

## Check or start the VM

1. Check its state and address:

   ```sh
   virsh -r -c qemu:///system domstate win11
   getent hosts win11.vm
   ```

2. If shut off, start it:

   ```sh
   virsh -c qemu:///system start win11
   ```

Use `qemu:///system` for this VM; plain `virsh` connects to the owner's separate user session.
Verification: `domstate` prints `running`.

## Open the Windows desktop

1. Open the console without needing guest networking:

   ```sh
   virt-viewer -c qemu:///system win11
   ```

2. For Remote Desktop, open Remmina, choose RDP, and connect to `win11.vm` as `vx`.
   Use the account password stored under `win11_password` in the encrypted `secrets/workloads.yaml`; keep it out of command arguments and logs.

Closing the viewer leaves Windows running.
Verification: the Windows desktop responds to keyboard and mouse input.

## Run commands over SSH

1. Connect with the owner's SSH key:

   ```sh
   ssh vx@win11.vm
   ```

   On the first connection, compare the offered host-key fingerprint with Windows before accepting it.
   In PowerShell through the VM console, print the ED25519 fingerprint:

   ```powershell
   & "$env:ProgramFiles\OpenSSH\ssh-keygen.exe" -lf "$env:ProgramData\ssh\ssh_host_ed25519_key.pub"
   ```

2. For automation, select the Windows shell explicitly and fail rather than prompt for credentials:

   ```sh
   ssh -o BatchMode=yes vx@win11.vm 'cmd.exe /c ver'
   ssh -o BatchMode=yes vx@win11.vm 'powershell.exe -NoProfile -NonInteractive -Command "Get-PSDrive -PSProvider FileSystem"'
   ```

Keep the remote command in single quotes on Linux so local shell expansion does not alter PowerShell variables or Windows paths.
SSH runs in a separate session; launch interactive desktop apps through the Windows desktop.
Verification: `cmd.exe /c ver` prints the Windows version.

## Exchange files

1. Open the host's shared drop folder:

   ```sh
   ls -la ~/workloads/win11/
   ```

2. Copy inputs into that folder with the host's file manager or shell.
   In Windows, open the shared drive under **This PC**; save outputs there to retrieve them from the same host folder.

   To look up its assigned drive letter, run from `~/nixos`:

   ```sh
   nix eval --raw .#nixosConfigurations.songbird.config.workloads.guests.win11.windows.virtiofs.driveLetters.drop
   ```

Verification: a file saved on either side appears on the other.
Deleting a file from the shared drive also deletes it from the host folder.

## Shut down or restart

Precondition: save open work in Windows.

1. Request a graceful shutdown, or use Windows Start > Power > Restart for a reboot:

   ```sh
   virsh -c qemu:///system shutdown win11
   ```

2. Check shutdown completion before starting it again:

   ```sh
   virsh -r -c qemu:///system domstate win11
   ```

Verification: a completed shutdown prints `shut off`.

## Diagnose a connection or share failure

1. Check the VM, name resolution, and provisioning log on Songbird:

   ```sh
   virsh -r -c qemu:///system domstate win11
   getent hosts win11.vm
   journalctl -u workloads-provision@win11.service -b -n 60 --no-pager
   ```

2. If SSH or RDP fails, use `virt-viewer` to inspect Windows directly.
   If provisioning failed, resolve the logged cause and rerun it:

   ```sh
   sudo systemctl restart workloads-provision@win11.service
   ```

Verification: the journal reports `guest 'win11' is provisioned`, and the failed connection or share works.

[Installation, activation, Office, and golden copies](songbird-runbook-win11.md) | [Windows provisioning troubleshooting](../../apps/libvirt/windows-troubleshooting.md)
