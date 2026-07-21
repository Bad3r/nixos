# Songbird NixOS Setup Plan

Decision-complete plan for bringing the `songbird` host into this
repository: dual-boot layout, firmware settings, install sequence, data
migration from system76, the per-host module files, and validation. Hardware
facts live in [project-songbird.md](project-songbird.md); the generic
onboarding mechanics live in the
[Host Onboarding Runbook](../guides/host-onboarding.md). Decisions below were
locked with the owner on 2026-07-21. The install is gated only by delivery of
disk A (the SN8100).

## Decision Record

| #   | Decision                                                                                                                                                                                                            |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Dual boot: NixOS is the daily OS, Windows 11 exists for gaming (and Windows-side local AI).                                                                                                                         |
| 2   | Disk A (SN8100 4TB, M.2_1) belongs entirely to NixOS: GPT with 1 GiB ESP, LUKS2 ext4 root, 64 GiB LUKS2 swap.                                                                                                       |
| 3   | Swap is 64 GiB so hibernation stays possible (48 GB RAM) and build/LLM spikes have headroom.                                                                                                                        |
| 4   | Disk B (2TB NVMe ex system76, M.2_2) belongs entirely to Windows 11 with BitLocker and its own ESP. NixOS never mounts B.                                                                                           |
| 5   | Disk S (Samsung 850 Pro 4TB SATA ex system76) becomes a shared BitLocker NTFS drive, unlocked on NixOS via `cryptsetup` bitlk and mounted at `/shared`.                                                             |
| 6   | Each OS keeps its own ESP on its own disk: Windows updates cannot touch the NixOS boot chain.                                                                                                                       |
| 7   | Default boot is systemd-boot on A. Windows is selected via the firmware boot menu (F8) or a one-shot `efibootmgr --bootnext`.                                                                                       |
| 8   | No chainloading Windows through systemd-boot: the NixOS `boot.loader.systemd-boot.windows` entries boot via the EDK2 UEFI shell, which disturbs BitLocker's TPM measurements (PCR 4) and provokes recovery prompts. |
| 9   | Secure Boot stays off (unsigned systemd-boot, fleet standard). BitLocker therefore binds to the non-PCR7 TPM profile; that is expected.                                                                             |
| 10  | Migration: contents of B (system76 root/home) and S (system76 /data) are copied to A before B is wiped for Windows and S is reformatted.                                                                            |
| 11  | Migrated data lands in `/data` as a plain directory on A's root filesystem (no separate partition).                                                                                                                 |
| 12  | `shareCommon = true`: songbird takes the full hosts-common baseline (zen kernel, systemd-boot, i3/X11, PipeWire, sops runtime, app baseline).                                                                       |
| 13  | GPU wiring via `flake.nixosModules.nvidia-gpu`: `open = true` (mandatory on Blackwell), production driver branch (>= 570 required), `vaapi.backend = "nvidia"` with `"intel-media"` as the documented fallback.     |
| 14  | songbird becomes the primary fleet endpoint: `primary = true` and a fresh `tailnetIp` move into its `policy.nix`; system76 stays a fleet member on replacement drives without those keys.                           |
| 15  | `system.stateVersion = "26.05"` (current stable at install time; never bumped afterwards).                                                                                                                          |
| 16  | Steam stays enabled on the NixOS side too (`programs.steam.extended.enable`), matching system76; Proton covers casual Linux-side gaming.                                                                            |
| 17  | Windows hibernation and Fast Startup are disabled (`powercfg /h off`); NixOS keeps hibernation. Cross-OS discipline rules in Operating Rules.                                                                       |

## Disk Layout

Disk A, `/dev/disk/by-id/nvme-WD_BLACK_SN8100_4TB_*` (partition with these
targets; UUIDs are harvested at install):

| Part | Size          | Type              | Content                            |
| ---- | ------------- | ----------------- | ---------------------------------- |
| p1   | 1 GiB         | EF00 (ESP)        | vfat, systemd-boot                 |
| p2   | rest - 64 GiB | 8309 (Linux LUKS) | LUKS2 -> ext4, NixOS root          |
| p3   | 64 GiB        | 8309 (Linux LUKS) | LUKS2 -> swap (hibernation resume) |

Disk B (Windows installer creates its own layout on the empty disk): Windows
ESP + MSR + C: (BitLocker). NixOS never mounts any of it.

Disk S: single GPT NTFS partition, BitLocker-encrypted, labeled `shared`.
Mounted by Windows with auto-unlock and by NixOS at `/shared` (bitlk).

Rationale for the split (recorded from the decision discussion): game loading
is random-read and decompression bound, so Gen5 vs Gen4/Gen3 NVMe is a
seconds-level difference at most and Windows loses nothing on B, while NixOS
work (LLM weights, /nix, /data) uses A's 4 TB and full sequential speed
daily. Separate disks also isolate the boot chains completely.

## Firmware (UEFI) Settings

Set once during Phase 6 of the assembly checklist (BIOS 3202 is already
flashed in Phase 1):

| Setting                       | Value                       | Why                                                              |
| ----------------------------- | --------------------------- | ---------------------------------------------------------------- |
| Secure Boot                   | Off                         | systemd-boot is unsigned (fleet standard)                        |
| TPM (Intel PTT)               | On                          | BitLocker on B and S                                             |
| Above 4G Decoding + ReBAR     | On                          | RTX 5080 performance; driver expects Resizable BAR               |
| VT-x and VT-d                 | On                          | kvm-intel (hosts-common), vfio headroom                          |
| XMP (DDR5-8400)               | On                          | Memtest ladder per assembly checklist: 8400 / 8000 / 7600 / 6400 |
| Fast Boot                     | Off                         | Reliable USB + initrd behavior                                   |
| Boot order (after all phases) | systemd-boot (disk A) first | NixOS is the default OS                                          |

## Hardware to NixOS Mapping

What each device needs from the configuration. "hosts-common" means it is
already covered by the shared baseline and needs no per-host code.

| Hardware                         | Driver / stack                     | Config source                                                          |
| -------------------------------- | ---------------------------------- | ---------------------------------------------------------------------- |
| 285K P/E cores, virtualization   | intel_pstate, kvm-intel, coretemp  | hosts-common (`boot.nix`); microcode via `hardware-config.nix`         |
| Arrow Lake iGPU (Xe-LPG)         | i915/xe, linux-firmware            | Present for bring-up; VA-API only if `vaapi.backend = "intel-media"`   |
| RTX 5080 (Blackwell GB203)       | NVIDIA open kernel modules, >= 570 | `modules/songbird/nvidia-gpu.nix` over `flake.nixosModules.nvidia-gpu` |
| Intel 2.5 GbE                    | igc (in-kernel)                    | Nothing needed; name feeds `firewallDnsInterfaces`                     |
| Realtek 5 GbE (RTL8126)          | r8169 (in-kernel since 6.8)        | Nothing needed; zen kernel is well past 6.8                            |
| Wi-Fi 7 module (vendor unlisted) | iwlwifi or mt76 + linux-firmware   | Identify at first boot (`lspci -nn`); in-kernel either way             |
| Bluetooth 5.4                    | btusb                              | `hardware.bluetooth.enable` in `hardware-config.nix`                   |
| USB audio codec (SupremeFX)      | PipeWire                           | hosts-common (`pipewire.nix`)                                          |
| NVMe (A, B) and SATA (S)         | nvme, ahci                         | hosts-common initrd module list already includes both                  |
| Thunderbolt 4 / USB4             | thunderbolt + bolt                 | `services.hardware.bolt.enable` in `hardware-config.nix`               |
| Board sensors                    | coretemp, nct6775 family           | Monitoring only; fan control lives in BIOS Q-Fan                       |
| AIO pump/fans                    | none (plain PWM)                   | No OS dependency by design                                             |

## Install Sequence

Runs inside the assembly flow of the build's
[assembly-checklist.md](https://github.com/Bad3r/project-songbird/blob/main/assembly-checklist.md)
(OS install is its Phase 6 step). Phases N1-N2 need only disk A; N3-N5 wait
for the drives pulled from system76.

### Phase N1: NixOS on disk A

1. Boot the NixOS 26.05 installer USB (prepared in assembly Phase 0). Wired
   network on either onboard NIC works out of the box.

2. Partition and encrypt (device path via `ls /dev/disk/by-id/`):

   ```sh
   DISK=/dev/disk/by-id/nvme-WD_BLACK_SN8100_4TB_<serial>
   sgdisk --zap-all "$DISK"
   sgdisk -n1:0:+1GiB  -t1:ef00 -c1:ESP        "$DISK"
   sgdisk -n2:0:-64GiB -t2:8309 -c2:cryptroot  "$DISK"
   sgdisk -n3:0:0      -t3:8309 -c3:cryptswap  "$DISK"
   cryptsetup luksFormat --type luks2 "$DISK-part2"
   cryptsetup luksFormat --type luks2 "$DISK-part3"
   cryptsetup open "$DISK-part2" cryptroot
   cryptsetup open "$DISK-part3" cryptswap
   mkfs.vfat -F32 -n ESP "$DISK-part1"
   mkfs.ext4 -L nixos /dev/mapper/cryptroot
   mkswap /dev/mapper/cryptswap
   mount /dev/mapper/cryptroot /mnt
   mkdir -p /mnt/boot && mount "$DISK-part1" /mnt/boot
   swapon /dev/mapper/cryptswap
   ```

3. Harvest hardware truth: `nixos-generate-config --root /mnt` and copy the
   UUIDs (LUKS partitions, ext4 root, ESP, swap) into
   `modules/songbird/hardware-config.nix`. The generated file itself is not
   committed; this repo's per-host module replaces it.

4. Clone the repo with the secrets submodule. The submodule is private, so
   the installer session needs the owner's SSH key (from an existing host or
   the password manager):

   ```sh
   git clone --recurse-submodules git@github.com:Bad3r/nixos.git
   cd nixos && git switch -c feat/songbird-host
   ```

5. Add the songbird module files (skeletons below), fill the UUID and
   hostId placeholders, then commit and push the branch. Committing is
   mandatory (flake evaluation only sees git-tracked files); pushing is too.
   This installer checkout lives on the live-ISO tmpfs and is discarded at
   reboot, and `nixos-install` copies only the store closure to `/mnt`, not
   this working tree, so the branch must reach the remote to survive into
   Phase N2:

   ```sh
   git push -u origin feat/songbird-host
   ```

6. Install with Lix (the repo's pinned Nix implementation; the ISO's CppNix
   also works pre-cutover with the same feature set):

   ```sh
   nix shell nixpkgs#lixPackageSets.latest.lix
   export NIX_CONFIG='experimental-features = nix-command flakes pipe-operator pipe-operators flake-self-attrs'
   nixos-install --root /mnt --flake .#songbird --no-root-passwd
   ```

   The owner account ships with an initial password hash from
   `modules/meta/owner.nix`; change it at first login.

### Phase N2: First boot and fleet integration

1. Log in and change the owner password (`passwd`). Clone the fleet checkout
   into the primary user's home and resume the branch pushed in Phase N1;
   `~/nixos` is the canonical checkout the worktree-prune timer expects on
   shared hosts, and it is owner-owned because the primary user creates it:

   ```sh
   git clone --recurse-submodules git@github.com:Bad3r/nixos.git ~/nixos
   cd ~/nixos && git switch feat/songbird-host
   ```

2. Provision the canonical age identity (sops), per
   [SOPS usage](../sops/README.md) Host Preparation: copy from system76 or
   the password manager to `/var/lib/sops-nix/key.txt` (root:root, 0600) and
   `~/.config/sops/age/keys.txt`. Single-recipient design: no `.sops.yaml`
   change, no `sops updatekeys`.

3. Flip `sopsRuntimeReady = true` in `modules/songbird/policy.nix`, rebuild
   with `./build.sh`, and confirm secret-consuming services activate.

4. Join the tailnet; read the assigned address with `tailscale ip -4` and set
   it as `tailnetIp` in `policy.nix`. In the same change move
   `primary = true` off `modules/system76/policy.nix` and onto songbird
   (ssh-hosts aliases and the tailscale SSH default follow the registry).

5. Record the host SSH public key
   (`cat /etc/ssh/ssh_host_ed25519_key.pub`) in `modules/songbird/ssh.nix`.

6. Fill remaining Open Items (interface names, Wi-Fi module vendor), run the
   validation ladder, and open the PR.

### Phase N3: Data migration from system76

Prerequisite: system76 has been moved onto its replacement drives (its own
task, outside this plan), so B and S are free to pull.

1. Install B in M.2_2 (never M.2_3/M.2_4: GPU lane steal) and S in the 2.5"
   sled, powered by this PSU's own modular SATA cable.
2. Boot NixOS, unlock the old volumes manually (`cryptsetup open` with the
   system76 passphrases), and copy:
   - B (old system76 root): `/home/<owner>` and anything else worth keeping
     into `/data/migration-system76/` on A.
   - S (old system76 /data, LUKS2 + XFS): contents into `/data/` on A.
3. Verify sizes and spot-check (`du -sh`, `diff -r` on samples). A has 4 TB;
   both source datasets fit.
4. Record disk B's exact model (`lsblk -o NAME,MODEL,SIZE`) in
   [project-songbird.md](project-songbird.md) Storage Inventory (S is the
   Samsung 850 Pro 4TB).
5. Leave B and S untouched until Phase N4/N5 confirm nothing was missed; the
   originals are the rollback until then.

### Phase N4: Windows 11 on disk B

1. Protect A's boot chain: disable the M.2_1 slot in UEFI (Advanced >
   Onboard Devices) if the firmware offers it; otherwise remove disk A
   (M.2_1 Q-Latch, board heatsink off). The Windows installer is known to
   drop its boot files onto whichever ESP it finds first.
2. Boot Windows 11 24H2+ installer USB, delete all partitions on B (contents
   already migrated), install to the empty disk. Windows creates its own ESP
   on B.
3. Post-install, in an elevated shell:
   - `powercfg /h off` (kills hibernation and Fast Startup in one; required
     for safe NTFS sharing).
   - `reg add "HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /t REG_DWORD /d 1 /f`
     (hardware clock stays UTC; NixOS default).
   - Enable BitLocker on C:. With Secure Boot off, Windows binds to the
     PCR 0,2,4,11 profile and warns about Secure Boot: expected (decision 9).
     Store the recovery key in the password manager.
4. Re-enable / reinstall disk A. In UEFI, put the `Linux Boot Manager`
   (systemd-boot on A) first in boot order; `Windows Boot Manager` (B)
   second.
5. Verify both OSes boot cleanly from the F8 firmware boot menu.

### Phase N5: Shared drive S

1. In Windows: wipe S (contents already migrated), create a single GPT NTFS
   volume labeled `shared`, enable BitLocker with a password protector plus
   recovery key, then `manage-bde -autounlock -enable <drive>:`. Store both
   password and recovery key in the password manager.
2. In NixOS: place the BitLocker password (no trailing newline) at
   `/var/lib/secrets/shared-bitlk.key`, root:root, 0400. A plain root-owned
   file on the LUKS-encrypted root is used instead of a sops runtime path
   because `systemd-cryptsetup@shared` runs from `cryptsetup.target`, before
   sops-nix activation writes `/run/secrets`; the crypttab generator adds
   `RequiresMountsFor=` on the key path, so ordering against the root mount
   is automatic.
3. The crypttab entry and mount ship in `hardware-config.nix` (skeleton
   below). Confirm with a reboot: `/shared` mounts owner-readable, and
   Windows still auto-unlocks.

## Per-Host Module Files

Registry entry in `modules/hosts/common/registry.nix`:

```nix
songbird.shareCommon = true;
```

`modules/songbird/hardware-config.nix` (placeholders in angle brackets come
from Phase N1 step 3 and Phase N5):

```nix
{ lib, ... }:
{
  configurations.nixos.songbird.module =
    { config, metaOwner, ... }:
    let
      owner = metaOwner.username;
    in
    {
      nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

      boot = {
        # hosts-common already provides the initrd module list (nvme, ahci,
        # xhci_pci, thunderbolt, usbhid, usb_storage, sd_mod); extend here
        # only if nixos-generate-config reports more.
        initrd.luks.devices = {
          cryptroot = {
            device = "/dev/disk/by-uuid/<luks-root-partition-uuid>";
            allowDiscards = true;
          };
          cryptswap = {
            device = "/dev/disk/by-uuid/<luks-swap-partition-uuid>";
            allowDiscards = true;
          };
        };

        # Hibernation target: swap inside the cryptswap mapping.
        resumeDevice = "/dev/mapper/cryptswap";

        loader.systemd-boot.configurationLimit = 5;
      };

      fileSystems = {
        "/" = {
          device = "/dev/mapper/cryptroot";
          fsType = "ext4";
        };
        "/boot" = {
          device = "/dev/disk/by-uuid/<esp-uuid>";
          fsType = "vfat";
          options = [
            "fmask=0077"
            "dmask=0077"
          ];
        };
        # Disk S: BitLocker NTFS, opened by the crypttab entry below.
        "/shared" = {
          device = "/dev/mapper/shared";
          fsType = "ntfs3";
          options = [
            "uid=1000"
            "gid=100"
            "windows_names"
            "noatime"
            "nofail"
          ];
        };
      };

      swapDevices = [ { device = "/dev/mapper/cryptswap"; } ];

      # BitLocker unlock for disk S. Key file provisioning: Phase N5.
      environment.etc."crypttab".text = ''
        shared /dev/disk/by-partuuid/<shared-partuuid> /var/lib/secrets/shared-bitlk.key bitlk,nofail
      '';

      hardware = {
        cpu.intel.updateMicrocode = true;
        bluetooth = {
          enable = true;
          powerOnBoot = true;
        };
      };

      # Thunderbolt 4 device authorization.
      services.hardware.bolt.enable = true;

      systemd.tmpfiles.rules = [
        "d /data 0755 ${owner} users -"
      ];
    };
}
```

`modules/songbird/nvidia-gpu.nix`:

```nix
_: {
  configurations.nixos.songbird.module =
    { config, ... }:
    {
      boot.blacklistedKernelModules = [ "nouveau" ];
      # Keep VRAM contents across suspend/hibernate (paired with the 64 GiB
      # swap and boot.resumeDevice).
      boot.kernelParams = [ "nvidia.NVreg_PreserveVideoMemoryAllocations=1" ];

      gpu.nvidia = {
        enable = true;
        # Blackwell (GB203): driver >= 570 and the open kernel modules are
        # mandatory; the proprietary modules do not support this GPU.
        package = config.boot.kernelPackages.nvidiaPackages.production;
        open = true;
        # NVDEC VA-API path. Fallback documented in decision 13: set
        # "intel-media" if Xid 31 MMU faults appear under decode churn.
        vaapi.backend = "nvidia";
      };
    };
}
```

`modules/songbird/policy.nix`:

```nix
_: {
  flake.lib.nixos.hosts.songbird = {
    # Primary fleet endpoint, moved from system76 in this change.
    primary = true;
    tailnetIp = "<songbird tailscale IPv4>";

    # Flip after the age identity is installed (Phase N2 step 2-3).
    sopsRuntimeReady = false;
    r2RuntimeReady = false;

    extraHomeApps = [ ];
    firewallDnsInterfaces = [ "<wired-interface-name>" ];
  };
}
```

`modules/songbird/host-id.nix` (derive on the target:
`head -c 8 /etc/machine-id`):

```nix
_: {
  configurations.nixos.songbird.module = {
    networking.hostId = "<8-hex-chars>";
  };
}
```

`modules/songbird/state-version.nix`:

```nix
_: {
  configurations.nixos.songbird.module = {
    # Install-time constant for this host. Never bump on upgrades.
    system.stateVersion = "26.05";
  };
}
```

`modules/songbird/ssh.nix`:

```nix
{ lib, ... }:
{
  configurations.nixos.songbird.module = {
    services.openssh = {
      enable = lib.mkDefault false;
      publicKey = "<ssh-ed25519 ... root@songbird>";
    };
  };
}
```

`modules/songbird/imports.nix`:

```nix
_: {
  configurations.nixos.songbird.module = {
    # Desktop board with no vendor NixOS module; the fleet baseline comes
    # from hosts-common, so no nixos-hardware import is needed.
    programs = {
      steam.extended.enable = true;
      rip.extended.enable = true;
    };
  };
}
```

`modules/songbird/nix-settings.nix`:

```nix
_: {
  configurations.nixos.songbird.module.nix.settings = {
    max-jobs = "auto"; # 24 threads, 48 GB RAM
    min-free = 53687091200; # 50 GB
  };
}
```

Companion change in the same PR: remove `primary = true` and `tailnetIp`
from `modules/system76/policy.nix` (system76 remains a fleet member).

## Booting Windows from NixOS

Default boot is systemd-boot on A. To boot Windows:

- Occasional use: F8 firmware boot menu, pick `Windows Boot Manager`.

- From a running NixOS session:

  ```sh
  sudo efibootmgr                     # note the Windows Boot Manager entry, e.g. Boot0002
  sudo efibootmgr --bootnext 0002 && systemctl reboot
  ```

  BootNext boots Windows exactly once through its own firmware entry, so
  BitLocker's measured chain stays clean; the next reboot returns to
  systemd-boot. Wrap as a `boot-windows` alias later if wanted.

Rejected: `boot.loader.systemd-boot.windows.*` entries (they chainload via
the EDK2 UEFI shell, changing PCR 4 and triggering BitLocker recovery
prompts) and any shared-ESP scheme (decision 6).

## Open Items

Every placeholder, with its source command and destination. No decisions
remain open; these are measurements that require the hardware.

| Item                        | Command / source                        | Lands in                                                                 |
| --------------------------- | --------------------------------------- | ------------------------------------------------------------------------ |
| LUKS, ext4, ESP, swap UUIDs | `nixos-generate-config --root /mnt`     | `hardware-config.nix`                                                    |
| hostId                      | `head -c 8 /etc/machine-id`             | `host-id.nix`                                                            |
| Wired interface names       | `ip link`                               | `policy.nix` `firewallDnsInterfaces`                                     |
| Wi-Fi module vendor         | `lspci -nn \| grep -i network`          | project-songbird.md (note)                                               |
| Host SSH public key         | `cat /etc/ssh/ssh_host_ed25519_key.pub` | `ssh.nix`                                                                |
| Tailnet IPv4                | `tailscale ip -4` after joining         | `policy.nix` `tailnetIp`                                                 |
| Disk B exact model          | `lsblk -o NAME,MODEL,SIZE`              | project-songbird.md Storage Inventory                                    |
| Shared partition PARTUUID   | `lsblk -o NAME,PARTUUID` after Phase N5 | `hardware-config.nix` crypttab entry                                     |
| BitLocker keys (B, S)       | Windows BitLocker setup                 | Password manager; S password also to `/var/lib/secrets/shared-bitlk.key` |

## Validation Ladder

Per the runbook, before and after the PR:

```sh
nix fmt
nix flake check --accept-flake-config --no-build --offline
nix build ".#nixosConfigurations.songbird.config.system.build.toplevel"
./build.sh --boot          # on songbird; activates on next reboot
nix run .#generation-manager -- score   # target: 20/20
```

Plus host-specific checks after first boot:

- `systemctl status systemd-cryptsetup@shared` and `ls /shared` (bitlk mount).
- `nvidia-smi` reports the RTX 5080 on the open kernel module (driver >= 570).
- `sensors` shows coretemp; `ip link` shows both NICs; Wi-Fi and Bluetooth
  associate.
- Hibernate round-trip (`systemctl hibernate`) after confirming
  `boot.resumeDevice`; NVIDIA VRAM survives (decision 13 kernel param).
- Assembly checklist Phase 7 load validation (CPU 30 min, GPU 30 min, SSD
  sustained write) fills the hardware validation log.

## Operating Rules (cross-OS)

1. Windows never hibernates and never fast-starts (`powercfg /h off`, Phase
   N4). This keeps B and S clean for every boot.
2. If NixOS is hibernated, resume NixOS. Do not boot Windows and write to S
   while NixOS holds a hibernation image with `/shared` mounted; on resume
   the stale page cache can corrupt NTFS. Boot Windows only after a clean
   NixOS shutdown or reboot.
3. Windows feature updates may reorder UEFI boot entries. Fix is
   `efibootmgr -o` (or UEFI setup); they cannot damage A's ESP (decision 6).
4. BitLocker recovery keys and the S password live in the password manager;
   losing them makes B or S unrecoverable.
5. NixOS-side writes to `/shared` use the kernel ntfs3 driver with
   `windows_names`, which blocks file names Windows cannot read.
6. Firmware updates (BIOS) reset boot order and can reset PTT: after any
   BIOS update, re-check boot order, Secure Boot off, and expect one
   BitLocker recovery-key prompt on Windows.
