# Songbird runbook: virtual machines

NixOS procedures are in [songbird-runbook.md](songbird-runbook.md); the libvirt setup itself is in [Workload VMs](../../workloads/vms.md).

## Run an ad-hoc guest on the default network

Precondition: the installer ISO sits at a path on songbird, and the generation that declares the `default` network is active.

1. Declare the ISO as media in `modules/hosts/songbird/workloads.nix`, beside the network:

   ```nix
   configurations.nixos.songbird.module.workloads.media.<name>.source = "<path to the ISO>";
   ```

2. Switch through [Validate a host change](songbird-runbook.md#validate-a-host-change), then confirm the copy:

   ```sh
   systemctl status workloads-vm-media.service
   ls -l /var/lib/workloads/media/
   ```

3. Start `virt-manager` and authenticate when it connects to `qemu:///system`.

4. Create the guest with File > New Virtual Machine:

   - Installation media: Browse > Browse Local, then `/var/lib/workloads/media/<name>`.
   - Network selection: Virtual network `default`.

   virt-manager keeps the guest's disk in its `default` storage pool under `/var/lib/libvirt/images`.

5. Install the guest from the console.

Verification, inside the guest:

```sh
ip -4 addr
curl -s https://1.1.1.1/cdn-cgi/trace | grep -E '^(ip|warp)='
```

The guest holds a lease from the `vn-default` range, and the trace reports `warp=on`.
From the guest, songbird's LAN address and the gateway answer nothing beyond DHCP, DNS, and ping, and other guests on `default` are unreachable.

## Drop a staged ISO

Precondition: no guest still boots from the ISO; detach it in the guest's CD-ROM settings first.

1. Remove its `workloads.media.<name>` declaration from `modules/hosts/songbird/workloads.nix`.
2. Switch through [Validate a host change](songbird-runbook.md#validate-a-host-change).

Verification: `ls /var/lib/workloads/media/` omits it, and `journalctl -u workloads-vm-media.service -b` logs the prune.
