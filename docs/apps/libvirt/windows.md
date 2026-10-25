# Windows guests

A `kind = "windows"` guest installs unattended from a seed CD-ROM and is then provisioned through its QEMU guest agent.
The pipeline and the `windows.*` options live in `modules/workloads/vms/windows/`; everything else about the guest follows [Declared libvirt guests](guests.md).

## Seed CD-ROM

`windows.seedIso` builds a CD-ROM labelled `XSEED` that holds no secret:

- `autounattend.xml`, rendered from the `windows` options;
- `$WinPEDriver$`, with the virtio storage and network drivers Setup needs to find the disk;
- the virtio-win guest tools, which bring the guest agent, the SPICE agent, and the other drivers;
- a hash-pinned Win32-OpenSSH installer;
- `firstlogon.ps1`.

While `install.media` is not empty, the seed is the `<name>-seed` entry of `workloads.images`, attached as a CD-ROM from the out-link `/var/lib/workloads/images/<name>-seed`.
A guest without NVRAM stays undefined, with a warning naming each fix, until that out-link leads to the current seed and every install medium is staged.

## Answer file

- Setup installs the `install.wim` image that `windows.edition` names onto a GPT disk, so the value matches an image name on the media.
- Setup names the computer after the guest, which caps guest names at 15 characters.
- Setup runs without a product key only from volume license media; consumer media stop at the key page.
- Secure Boot with the TPM passes the hardware checks without registry bypasses.
- Device encryption stays off and the out-of-box screens are skipped.
- One local administrator, `windows.account.name`, gets a blank password and a single autologon; Windows refuses blank passwords over the network.
- The autologon runs `firstlogon.ps1`: guest tools, OpenSSH, hibernation and Fast Startup off, no sleep timeouts, no password expiry.

`firstlogon.ps1` logs to `C:\ProgramData\workloads\firstlogon.log` and ends by writing `firstlogon.done`, or `firstlogon.failed` with the error.
Installers run from `C:\ProgramData\workloads` as SYSTEM, so `firstlogon.ps1` restricts it to SYSTEM and Administrators, and every provisioning run first restores that.

## Provisioning

A libvirt hook queues `workloads-provision@<name>.service` when the guest starts or libvirtd reconnects to it, and stops the unit when the guest stops.
A tmpfiles link puts the hook in place at the switch that adds it, but libvirtd looks for qemu hooks only when it starts.
When it started without one, the hook stays silent until libvirtd restarts, as [workloads-provision never starts](#workloads-provision-never-starts) describes.
The active unit stands for a provisioned run of the guest; a switch never restarts it, so changed steps run at the next start of the guest.

While the OS disk is still empty, the unit presses Enter for the installer's boot prompt.
It waits through the installation for the guest agent and for `firstlogon.ps1`, then runs the steps in order:

1. Password: libvirt sets it from the `windows.account.passwordSecret` file, never through a command line.
2. SSH keys: `administrators_authorized_keys` holds `windows.account.authorizedKeys`, readable by SYSTEM and Administrators only.
3. Remote Desktop: on, with its built-in firewall group open to the gateway of each guest network only.
4. Firewall: one `workloads-<service>` rule per `windows.services` entry, open to the same gateways; undeclared `workloads-*` rules are removed.
   `firstlogon.ps1` removes the rule the OpenSSH installer adds, so port 22 follows `windows.services` too.
5. Shares: WinFsp and the drive letter of each declared share, as [Guest shares](shares.md#windows-guests) describes.
6. Product key: with `windows.productKeySecret` set and its file present, the licensing calls behind `slmgr.vbs /ipk` and `/ato` install and activate it; otherwise provisioning leaves activation as it is.
7. Office: with `windows.office.installer` set and no Microsoft 365 or Office suite listed under Apps, the staged installer is copied into the guest and run there.
   It downloads Office from Microsoft, and signing in to an Office app with the account that owns the subscription licenses it.

Every step but the password probes the guest first, changes only what differs, and probes again.
The Office step waits for any running Click-to-Run install, then polls until the suite is listed and Click-to-Run is idle.
It stops the installer's process tree once Office is in place, or at its time limit, when the step fails.
The product key travels on the guest program's standard input and the password through the agent's set-password command, so no process list shows either.
libvirtd debug logging records guest agent commands, and with them both secrets.
A restart reruns every step, for instance after a secret changed:

```sh
sudo systemctl restart workloads-provision@<name>.service
```

## Secrets

The host declares the account password as a `sops.secrets` entry and names it in `windows.account.passwordSecret`; a product key works the same way through `windows.productKeySecret`.
Each is a flat key in an encrypted file, created as [Adding a Secret](../../sops/adding-secrets.md) describes:

```sh
sops secrets/<file>.yaml
```

The provisioning unit reads them as root at runtime, so no secret enters the store or the seed.

## Take a golden copy

Precondition: the guest is shut off without a managed save image.

1. From a session on the host, start the copy and authenticate at the prompt:

   ```sh
   systemctl start workloads-golden@<name>.service
   ```

2. Read its log:

   ```sh
   journalctl -u workloads-golden@<name>.service -b
   ```

The unit copies the disks, NVRAM, TPM state, and inactive domain XML of any declared guest sparsely into `/var/lib/workloads/golden/<uuid>/`.
It refuses a running guest, files that change during the copy, and an existing golden directory, which is moved aside by hand first.

Verification: the log ends with `copied guest '<name>'`.

## Restore a golden copy

Precondition: the guest is shut off without a managed save image.

1. Move the current state aside and copy the golden one in, as root:

   ```sh
   cd /var/lib/workloads
   mv guests/<uuid> guests/<uuid>.replaced
   cp --archive --sparse=always golden/<uuid> guests/<uuid>
   rm guests/<uuid>/domain.xml
   ```

2. Restart `workloads-vm-guest-<name>.service`, then start the guest.

Verification: the guest boots into the golden state; `guests/<uuid>.replaced` stays until deleted by hand.

## A Windows guest stays undefined

Cause: the seed out-link is missing or older than the declaration, or an install medium is not staged.

```sh
journalctl -u workloads-vm-guest-<name>.service -b -p warning
```

Fix: run the commands the warning names, which build the seed and restart the media and guest units.

## workloads-provision fails

Cause: a step failed in the guest, `firstlogon.ps1` failed, or the guest agent refused a command.

```sh
journalctl -u workloads-provision@<name>.service -b
```

Fix: a `firstlogon.ps1` failure quotes its error, and `C:\ProgramData\workloads\firstlogon.log` has the rest.
A guest shut down while `firstlogon.ps1` ran leaves neither marker, and the unit times out.
After fixing the cause on the console, delete any `firstlogon.failed`, run `powershell -ExecutionPolicy Bypass -File <drive>:\firstlogon.ps1` from the `XSEED` drive in an administrator console, and restart the unit.
A failed password step means the guest agent cannot set passwords, and the account keeps its blank password until it can.

## workloads-provision never starts

Cause: libvirtd started before any qemu hook existed, so it never calls one; a reload does not look for hooks again.

```sh
ls -l /var/lib/libvirt/hooks/qemu.d/
systemctl status 'workloads-provision@*'
```

Fix: restart libvirtd.
Running guests keep running, and libvirtd reconnects to them, which queues their provisioning:

```sh
sudo systemctl restart libvirtd.service
```
