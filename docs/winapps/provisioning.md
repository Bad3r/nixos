# WinApps guest provisioning

The rules that keep guest state safe are in [README.md](README.md), and baseline and disk procedures in [storage.md](storage.md).
Commands run on the host unless a step names the guest.

## Apply the declaration

Precondition: the host module sets `host.virtualization.windowsGuest.enable`, and `/` has room for the declared volume capacity plus 20 GiB.

1. Check the free space:

   ```sh
   df -h /
   ```

2. Build and switch from the repository root:

   ```sh
   ./build.sh
   ```

3. Log out and back in, so the session carries the new groups and `LIBVIRT_DEFAULT_URI`.

4. Check the NixVirt run and the declared objects:

   ```sh
   systemctl show --property=Result nixvirt.service
   virsh --connect qemu:///system net-list --all
   virsh --connect qemu:///system pool-list --all
   virsh --connect qemu:///system vol-info --pool winapps RDPWindows.qcow2
   virsh --connect qemu:///system list --all
   ```

Verification: the unit result is `success`, the `winapps` network and pool are active, the volume allocation is far below its capacity, and `RDPWindows` is shut off.

## Attach the install media

Precondition: a Windows 11 x64 ISO of an edition that hosts Remote Desktop is on the host, and the guest is shut off.

1. Move the ISO into the pool directory; QEMU runs as an unprivileged user that cannot read a home directory:

   ```sh
   pool=$(virsh --connect qemu:///system pool-dumpxml winapps --xpath '//target/path/text()')
   sudo mv ~/Downloads/<windows-iso> "$pool/windows.iso"
   sudo chown root:root "$pool/windows.iso"
   sudo chmod 0644 "$pool/windows.iso"
   ```

2. Set `host.virtualization.windowsGuest.installIso` to that path in the host module, then run `./build.sh`.
   The option also attaches the virtio-win driver ISO.

Verification: `virsh --connect qemu:///system domblklist RDPWindows --inactive` lists the Windows ISO and a virtio-win ISO.

## Install Windows

Precondition: the install media is attached.

1. Open the `RDPWindows` console in virt-manager, start the guest, and press a key at the CD boot prompt.

2. At the disk selection screen choose `Load driver`, browse the virtio-win CD to `viostor\w11\amd64`, and install the storage driver.
   The disk appears once the driver loads.

3. Create a local account named after the Linux user, and give it a password; RDP refuses an account without one.
   Pick `Domain join instead` under the sign-in options, or stay offline and pick `I don't have internet`.
   If setup offers neither, press Shift+F10, run `oobe\bypassnro`, and repeat the step after the restart.

Verification: at the desktop, in an elevated PowerShell in the guest, `Confirm-SecureBootUEFI` prints `True` and `Get-Tpm` reports `TpmPresent : True`.

## Install guest tools

Precondition: Windows is at the desktop and the virtio-win CD is attached.

1. In the guest, run `virtio-win-guest-tools.exe` from the root of the virtio-win CD, accept the defaults, and restart.
   It installs the remaining VirtIO drivers, the network driver among them, and the QEMU guest agent.

2. Check the agent and the address:

   ```sh
   virsh --connect qemu:///system qemu-agent-command RDPWindows '{"execute":"guest-ping"}'
   virsh --connect qemu:///system domifaddr RDPWindows --source agent
   virsh --connect qemu:///system net-dhcp-leases winapps
   ```

Verification: the agent answers `{"return":{}}`, and the lease holds the address of `host.virtualization.windowsGuest.network.guestAddress`.

## Configure Windows

Precondition: the guest tools are installed and the guest reaches the internet.

1. In an elevated PowerShell in the guest, turn sleep and hibernation off; a sleeping guest stops answering RDP:

   ```powershell
   powercfg /change standby-timeout-ac 0
   powercfg /change hibernate-timeout-ac 0
   powercfg /hibernate off
   ```

2. Run Windows Update until it offers nothing more, restarting when asked.

3. Install the Windows applications the guest exists for.

Verification: `powercfg /a` in the guest lists hibernation as unavailable, and Windows Update reports the guest up to date.

## Check guest isolation

Precondition: the guest is running with network access.

1. Read the host address on the guest bridge:

   ```sh
   ip -4 -br addr show virbr-winapps
   ```

2. In a PowerShell in the guest, probe the host and the internet:

   ```powershell
   Test-NetConnection <host-bridge-address> -Port 22
   Resolve-DnsName example.com
   Test-NetConnection example.com -Port 443
   ```

3. On a host that runs a VPN or WARP tunnel, repeat step 2 with the tunnel connected and disconnected.

Verification: the probe of the host fails, while the name lookup and the outbound connection succeed in every tunnel state.

## Detach the install media

Precondition: Windows, the guest tools, and the updates are installed.

1. Remove the `installIso` line from the host module, then run `./build.sh`.

2. Shut the guest down, wait until `domstate` prints `shut off`, and start it, so the new definition applies:

   ```sh
   virsh --connect qemu:///system shutdown RDPWindows
   virsh --connect qemu:///system domstate RDPWindows
   virsh --connect qemu:///system start RDPWindows
   ```

3. Delete the ISO:

   ```sh
   sudo rm "$(virsh --connect qemu:///system pool-dumpxml winapps --xpath '//target/path/text()')/windows.iso"
   ```

Verification: `virsh --connect qemu:///system domblklist RDPWindows` shows one CD drive with no source.
