# Windows guest troubleshooting

[Windows guests](windows.md) covers installation, provisioning, and golden copies.

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
