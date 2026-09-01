# Songbird NixOS Setup Plan

Decision-complete plan for bringing the `songbird` host into this
repository: dual-boot layout, firmware settings, install sequence, data
migration from system76, the per-host module files, and validation. Hardware
facts live in [project-songbird.md](project-songbird.md); the generic
onboarding mechanics live in the
[Host Onboarding Runbook](../guides/host-onboarding.md). Decisions below are
locked.

Status: Phases N0 and N1 are done. Disk A carries a NixOS
install (the installer's stock configuration, hostname `nixos`, still boots
it), and `modules/songbird/` holds the hardware truth harvested from that
machine, so the host builds from this repository. Where the machine differs
from the plan, the tables below carry the as-built values and note the plan
value in place. What remains is Phase N2 (first switch, tailnet, host key pin)
and the Windows phases N3 to N5.

## Decision Record

| #   | Decision                                                                                                                                                                                                                                                             |
| --- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Dual boot: NixOS is the daily OS, Windows 11 exists for gaming (and Windows-side local AI).                                                                                                                                                                          |
| 2   | Disk A (SN8100 4TB, M.2_1) belongs entirely to NixOS: GPT with 1 GiB ESP, LUKS2 ext4 root, LUKS2 swap. As built the swap is 51 GiB (the plan said 64 GiB); it still exceeds the 46 GiB of usable RAM, so hibernation stays possible.                                 |
| 3   | Swap is sized for hibernation (48 GB RAM) with headroom for build and LLM spikes.                                                                                                                                                                                    |
| 4   | One SSD belongs entirely to Windows 11 with BitLocker and its own ESP.                                                                                                                                                                                               |
| 5   | The shared drive is the WDC SN720 1TB (NTFS label `WD 1 TB`), mounted on NixOS at `/shared` through the kernel ntfs3 driver with `nofail`. The BitLocker conversion the plan scheduled for a SATA drive is deferred to Phase N5 and targets this one.                |
| 6   | Each OS keeps its own ESP on its own disk: Windows updates cannot touch the NixOS boot chain.                                                                                                                                                                        |
| 7   | Default boot is systemd-boot on A. Windows is selected via the firmware boot menu (F8) or a one-shot `efibootmgr --bootnext`.                                                                                                                                        |
| 8   | No chainloading Windows through systemd-boot: the NixOS `boot.loader.systemd-boot.windows` entries boot via the EDK2 UEFI shell, which disturbs BitLocker's TPM measurements (PCR 4) and provokes recovery prompts.                                                  |
| 9   | Secure Boot stays off (unsigned systemd-boot, fleet standard). BitLocker therefore binds to the non-PCR7 TPM profile; that is expected.                                                                                                                              |
| 10  | Disk S (Samsung 860 PRO 2TB, LUKS2 + XFS) is mounted at `/data` and unlocked in the initrd.                                                                                                                                                                          |
| 11  | `/data` is the mounted XFS volume, not a plain directory on A as the plan said.                                                                                                                                                                                      |
| 12  | `shareCommon = true`: songbird takes the full hosts-common baseline (systemd-boot, i3/X11, PipeWire, sops runtime, app baseline). `modules/songbird/cachyos-kernel.nix` is host-specific and overrides the common `linuxPackages_zen` default.                       |
| 13  | GPU wiring via `flake.nixosModules.nvidia-gpu`: `open = true` (NVIDIA's open kernel modules, mandatory on Blackwell), production driver branch (>= 570 required), `nouveau` blacklisted, `vaapi.backend = "nvidia"` with `"intel-media"` as the documented fallback. |
| 14  | songbird becomes the primary fleet endpoint (`primary = true` and `tailnetIp` in its `policy.nix`) once it has joined the tailnet; until the address exists the keys stay on system76 so the tailscale SSH alias on the other hosts keeps a HostName.                |
| 15  | `system.stateVersion = "26.11"`: disk A was installed from a 26.11pre image with that value, so the plan's `26.05` does not apply. Never bumped afterwards.                                                                                                          |
| 16  | Steam stays enabled on the NixOS side too (`programs.steam.extended.enable`), matching system76; Proton covers casual Linux-side gaming.                                                                                                                             |
| 17  | Windows hibernation and Fast Startup are disabled (`powercfg /h off`); NixOS keeps hibernation. Cross-OS discipline rules in Operating Rules.                                                                                                                        |
| 18  | Disk A first got a disposable Windows install (Phase N0) to validate firmware and hardware with vendor tools, then N1 wiped A for the NixOS install. Both done.                                                                                                      |

## Disk Layout

Disk A, `/dev/disk/by-id/nvme-WD_BLACK_SN8100_4000GB_252415800489`, as
built:

| Part | Size    | Type              | Content                                         | UUIDs                                                                                    |
| ---- | ------- | ----------------- | ----------------------------------------------- | ---------------------------------------------------------------------------------------- |
| p1   | 1 GiB   | EF00 (ESP)        | vfat, systemd-boot, `/boot`                     | `3028-D139`                                                                              |
| p2   | 3.6 TiB | 8309 (Linux LUKS) | LUKS2 -> ext4 root (`cryptroot`)                | LUKS `655308da-05a9-4989-95d0-7ac3f24a5f57`, ext4 `11785731-d139-4551-bff4-9e3a0d80c00e` |
| p3   | 51 GiB  | 8309 (Linux LUKS) | LUKS2 -> swap (`cryptswap`, hibernation resume) | LUKS `d776cdd8-ab0f-4081-abc0-c0e11b1aa6da`, swap `cf9f0148-18a4-4a1b-96ad-8677571fb609` |

Disk S (Samsung 860 PRO 2TB, SATA `0000:80:17.0`): a single LUKS2 partition,
header UUID `183d1f98-e95d-4d6c-89de-cbed409bd9a0`, opened as
`/dev/mapper/data` and holding the XFS `/data` volume.

Disk W (WDC PC SN720 1TB, chipset M.2 `0000:82:00.0`): a single NTFS
partition on an MBR table, filesystem UUID `1AE668D2E668B025`, label
`WD 1 TB`, mounted at `/shared`.

Windows gets its own disk, with its own ESP + MSR + C: (BitLocker).

## Firmware (UEFI) Settings

Set during Phase 6 of the assembly checklist and exercised under the
temporary Windows in Phase N0. BIOS 3305 is flashed; the plan referenced 3202.

| Setting                       | Value                       | Why                                                              |
| ----------------------------- | --------------------------- | ---------------------------------------------------------------- |
| Secure Boot                   | Off                         | systemd-boot is unsigned (fleet standard)                        |
| TPM (Intel PTT)               | On                          | BitLocker                                                        |
| Above 4G Decoding + ReBAR     | On                          | RTX 5080 performance; driver expects Resizable BAR               |
| VT-x and VT-d                 | On                          | kvm-intel (hosts-common), vfio headroom                          |
| XMP (DDR5-8400)               | On                          | Memtest ladder per assembly checklist: 8400 / 8000 / 7600 / 6400 |
| Fast Boot                     | Off                         | Reliable USB + initrd behavior                                   |
| Boot order (after all phases) | systemd-boot (disk A) first | NixOS is the default OS                                          |

## Hardware to NixOS Mapping

Full device table in [project-songbird.md](project-songbird.md).
"hosts-common" means the shared baseline already covers it and no per-host
code is needed.

| Hardware                                                                  | Driver / stack                                              | Config source                                                                                      |
| ------------------------------------------------------------------------- | ----------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| 285K P/E cores, virtualization                                            | intel_pstate, kvm-intel, coretemp                           | hosts-common (`boot.nix`); microcode via `hardware-config.nix`                                     |
| Arrow Lake NPU 4 (`0000:00:0b.0`)                                         | intel_vpu, intel-npu-driver firmware                        | `hardware.cpu.intel.npu.enable` in `hardware-config.nix`                                           |
| Arrow Lake iGPU Xe-LPG (`8086:7d67`, `0000:00:02.0`)                      | i915 (xe also loaded), linux-firmware                       | Present for bring-up; VA-API only if `vaapi.backend = "intel-media"`                               |
| RTX 5080 (GB203, `10de:2c02`, `0000:02:00.0`)                             | NVIDIA open kernel modules, production driver branch        | `modules/songbird/nvidia-gpu.nix` over `flake.nixosModules.nvidia-gpu`; `nouveau` blacklisted      |
| Realtek RTL8126 5 GbE (`0000:84:00.0`, the wired uplink)                  | r8169 (in-kernel, `rtl8126a` firmware)                      | `eth0` under `net.ifnames=0` (enumeration order, not pinned)                                       |
| Intel I226-V 2.5 GbE (`0000:85:00.0`)                                     | igc (in-kernel)                                             | `eth1` under `net.ifnames=0` (enumeration order, not pinned)                                       |
| Intel BE200 Wi-Fi 7 (`8086:272b`, `0000:86:00.0`)                         | iwlwifi + iwlmld, linux-firmware                            | Nothing needed; `wlan0` under `net.ifnames=0`                                                      |
| Bluetooth 5.4 (Intel, USB `8087:0036`)                                    | btusb + btintel                                             | `flake.nixosModules.bluetooth` (hosts-common); `KernelExperimental` added in `hardware-config.nix` |
| Audio: SupremeFX USB codec (`0b05:1b7c`), HDA `0000:80:1f.3`, NVIDIA HDMI | snd_usb_audio, snd_hda_intel (SOF path available), PipeWire | hosts-common (`pipewire.nix`); `sof-firmware` in `hardware-config.nix`                             |
| NVMe and SATA disks                                                       | nvme, ahci                                                  | hosts-common initrd module list                                                                    |
| Thunderbolt 4 / USB4 (`0000:00:0d.2`)                                     | thunderbolt + bolt                                          | `services.hardware.bolt.enable` in `hardware-config.nix`                                           |
| Board sensors                                                             | coretemp, `asus` WMI hwmon, spd5118, nvme                   | Monitoring only; fan control lives in BIOS Q-Fan                                                   |
| AIO pump/fans                                                             | none (plain PWM)                                            | No OS dependency by design                                                                         |

## Install Sequence

Runs inside the assembly flow of the build's
[assembly-checklist.md](https://github.com/Bad3r/project-songbird/blob/main/assembly-checklist.md)
(OS install is its Phase 6 step). Phases N0 and N1 needed only disk A and are
done; N2 is the first switch from this repository; N3 to N5 cover the drives
that came from system76 and the Windows install.

### Phase N0: Temporary Windows on disk A (done)

A disposable Windows 11 install on disk A validated the firmware settings and
the hardware with vendor tools (assembly-checklist Phase 7 load work: memory
at the laddered XMP profile, 30-minute CPU and GPU loads, SN8100 sustained
write under the M.2_1 heatsink, displays, USB4, both NICs, Wi-Fi, Bluetooth)
and applied Windows-only firmware updates. Phase N1 wiped it.

### Phase N1: NixOS installation on disk A (done)

Disk A was partitioned to the layout above and installed from a NixOS
26.11pre image with the installer's stock configuration (hostname `nixos`,
GNOME, `linuxPackages_latest`, `system.stateVersion = "26.11"`). That
configuration is what boots until Phase N2 switches the host to this
repository; it is not committed here. For a reinstall, the partition and
encrypt sequence was:

```sh
DISK=/dev/disk/by-id/nvme-WD_BLACK_SN8100_4000GB_252415800489
sgdisk --zap-all "$DISK"
sgdisk -n1:0:+1GiB  -t1:ef00 -c1:ESP        "$DISK"
sgdisk -n2:0:-51GiB -t2:8309 -c2:cryptroot  "$DISK"
sgdisk -n3:0:0      -t3:8309 -c3:cryptswap  "$DISK"
cryptsetup luksFormat --type luks2 "$DISK-part2"
cryptsetup luksFormat --type luks2 "$DISK-part3"
cryptsetup open "$DISK-part2" cryptroot
cryptsetup open "$DISK-part3" cryptswap
mkfs.vfat -F32 -n ESP "$DISK-part1"
mkfs.ext4 -L root /dev/mapper/cryptroot
mkswap -L swap /dev/mapper/cryptswap
```

After a reinstall, re-harvest the UUIDs (`nixos-generate-config --show-hardware-config`,
`lsblk -o NAME,FSTYPE,UUID`) into `modules/songbird/hardware-config.nix` and
the hostId (`head -c 8 /etc/machine-id`) into `modules/songbird/host-id.nix`;
the values there are the current install's.

### Phase N2: Fleet integration (first switch from this repository)

Run on songbird. Until the `feat/songbird-host` branch merges, run from its
linked worktree (`~/trees/nixos/feat-songbird-host`); afterwards from the
canonical `~/nixos` checkout on `main`, which is the path the shared
`worktree-prune` timer and `programs.nh.flake` expect.

1. Keep the `secrets/` submodule uninitialized until step 3 has installed the
   age identity: every sops declaration is guarded on the encrypted file
   existing, so a secretless checkout evaluates and activates cleanly, while a
   checkout with the payloads present but no key fails activation at the
   sops-nix step.

2. Build and stage the first generation, then reboot:

   ```sh
   cd ~/trees/nixos/feat-songbird-host
   nix shell nixpkgs#git nixpkgs#nh -c ./build.sh -t songbird --boot
   ```

   Two parts of that invocation are specific to the installer's stock system.
   It ships no `git`, and both the Nix git fetcher (which fetches the
   `secrets/` gitlink) and the secrets guard shell out to one, so without the
   `nix shell` wrapper the run stops at `executing "git": No such file or directory`; `nix develop path:.` cannot supply it, because evaluating the
   flake is what needs git in the first place. And `build.sh` takes the flake
   directory from the working directory, not from where the script lives, so
   a run started from `~/nixos` evaluates `git+file:///home/vx/nixos` on
   `main` and fails with `does not provide attribute ...nixosConfigurations.songbird`; `-p <dir>` names the directory
   explicitly. `-t songbird` is required for this first run only: `build.sh`
   defaults the target to `$(hostname)`, which is still `nixos` under the
   installer's configuration. `--boot` installs the generation for the next reboot
   instead of switching the running GNOME session live; from a linked
   worktree the script resolves a `path:` reference and runs the secrets
   guard on its own. Nothing already in `$HOME` blocks the first Home
   Manager activation: a file it manages is moved to `<file>.hm.bk`
   (`home-manager.backupFileExtension`), and a Firefox profile directory
   that the installer's Firefox left at `~/.config/mozilla/firefox` is moved
   to `<dir>.<timestamp>.hm.bk`, since that root has to be a symlink to
   `~/.mozilla/firefox` (`modules/browsers/_gecko-mk-profile.nix`). Claude
   Code is installed with bun during activation
   (`modules/songbird/apps-enable.nix`), which needs the npm registry
   reachable; an offline activation keeps whatever is already installed. At
   boot, the initrd asks for the root passphrase and retries it from the
   kernel keyring for `cryptswap` and `data`. The `/data` volume already has
   the root passphrase key slot listed below, so the unattended retry should
   unlock it without a second prompt. If a replacement volume lacks that key
   slot, add it once with `cryptsetup luksAddKey` using the device UUID from
   `hardware-config.nix`; until then, open the device as `data` and mount
   `/data` after login. An absent drive still does not block the boot. The `vx`
   account keeps the
   password set during the install (`users.mutableUsers` is on, so the
   initial hash in `modules/meta/owner.nix` is not applied to an existing
   user).

3. Provision the canonical age identity (sops), per
   [SOPS usage](../sops/README.md) Host Preparation: copy from system76 or
   the password manager to `/var/lib/sops-nix/key.txt` (root:root, 0600) and
   `~/.config/sops/age/keys.txt`. Single-recipient design: no `.sops.yaml`
   change, no `sops updatekeys`.

4. Initialize the secrets submodule (`git submodule update --init --recursive`),
   flip `sopsRuntimeReady = true` in `modules/songbird/policy.nix`
   (`r2RuntimeReady = true` as well once `secrets/r2.yaml` is present),
   rebuild with `./build.sh`, and confirm secret-consuming services activate.
   `secrets/songbird.yaml` with a `samba_media_path` key enables the
   on-demand Samba media share the way `secrets/system76.yaml` does on
   system76; until it exists `services.nix` warns and skips the share.
   Flipping `r2RuntimeReady` activates the R2 services and their `/data` path
   setup from `modules/lib/r2-runtime.nix`. The `nofail` mount is intentionally
   allowed to remain absent: `r2-runtime-paths.service` provisions
   `/data/r2`, `/data/fonts`, and `/data/Docs`, and every mount, bisync, and
   restic unit is ordered after it under `ConditionPathIsMountPoint=/data`, so
   a boot without the Samsung 860 leaves them inactive rather than building the
   tree on the root filesystem and syncing into it. Recovering after a late
   manual mount is `systemctl start r2-runtime-paths.service` plus the writer
   the workload needs; a condition-skipped boot job is not retried.

   When the disabled warning fires, it names the terms actually unmet, so a
   present `secrets/r2.yaml` is never listed as missing.

5. Join the tailnet; read the assigned address with `tailscale ip -4` and set
   it as `tailnetIp` in `policy.nix`. In the same change move
   `primary = true` off `modules/system76/policy.nix` and onto songbird
   (ssh-hosts aliases and the tailscale SSH default follow the registry).

6. The host SSH public key is pinned in `modules/songbird/ssh.nix` and as the
   `songbird` entry in `modules/hosts/common/ssh-known-hosts.nix`.

7. Run the validation ladder and merge the PR.

### Phase N3: Migration from system76

`/data` needs no migration because it is already mounted with its contents.
What remains is system76's root and home:

1. Confirm `/data` is mounted before copying anything into it: `findmnt /data`.
   Phase N2 step 2 records that the initrd abandons the `data` volume until the
   root passphrase is added as a key slot, and the mount is `nofail`, so until
   then `/data` is an empty directory on the root ext4 and `rsync` fills `/`
   without an error. Then, with system76 running on its replacement drives,
   copy `/home/<owner>` and anything else worth keeping over the network into
   `/data/migration-system76/` on songbird (`rsync -aHAX --info=progress2`
   over SSH; both hosts carry each other's `<host>.local` SSH alias once the
   key pin from Phase N2 is merged).
2. Verify sizes and spot-check (`du -sh`, `diff -r` on samples).
3. Leave the system76 originals untouched until Phase N4/N5 confirm nothing
   was missed; they are the rollback until then.

### Phase N4: Final Windows installation

1. Protect A's boot chain: disable the M.2_1 slot in UEFI (Advanced >
   Onboard Devices) if the firmware offers it; otherwise remove disk A
   (M.2_1 Q-Latch, board heatsink off). The Windows installer is known to
   drop its boot files onto whichever ESP it finds first. Disks S and W can
   stay: the installer only writes to the disk it is pointed at, but
   unplugging W avoids the wrong-drive mistake.

2. Boot Windows 11 24H2+ installer USB, delete all partitions on the target,
   install to the empty disk. Windows creates its own ESP there.

3. Post-install, in an elevated shell:

   - `powercfg /h off` (kills hibernation and Fast Startup in one; required
     for safe NTFS sharing).
   - `reg add "HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /t REG_DWORD /d 1 /f`
     (hardware clock stays UTC; NixOS default).
   - Enable BitLocker on C:. With Secure Boot off, Windows binds to the
     PCR 0,2,4,11 profile and warns about Secure Boot: expected (decision 9).
     Store the recovery key in the password manager.

4. Re-enable / reinstall disk A. In UEFI, put the `Linux Boot Manager`
   (systemd-boot on A) first in boot order; `Windows Boot Manager` second.

5. Verify both OSes boot cleanly from the F8 firmware boot menu.

### Phase N5: Shared BitLocker conversion of W (optional)

`/shared` works today as plain NTFS. Convert only if the shared drive must be
encrypted at rest:

1. In Windows: back up W's contents, wipe it, create a single GPT NTFS
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

3. In `modules/songbird/hardware-config.nix`, switch the `/shared` entry's
   `device` to `/dev/mapper/shared` and add the crypttab entry:

   ```nix
   environment.etc."crypttab".text = ''
     shared /dev/disk/by-partuuid/<shared-partuuid> /var/lib/secrets/shared-bitlk.key bitlk,nofail
   '';
   ```

4. Confirm with a reboot: `/shared` mounts owner-readable, and Windows still
   auto-unlocks.

## Per-Host Module Files

Registry entry in `modules/hosts/common/registry.nix`:

```nix
songbird.shareCommon = true;
```

The host directory mirrors `modules/system76/` minus the System76 chassis
stack (EC power daemon, PRIME, legacy driver branch, lid and touchpad
handling) and plus the desktop-specific pieces:

| File                                                            | Carries                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| --------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `modules/songbird/cachyos-kernel.nix`                           | Host-specific CachyOS overlay and `boot.kernelPackages` override over the common `linuxPackages_zen` default; the kernel and its NVIDIA module are built locally                                                                                                                                                                                                                                                                                                        |
| `modules/songbird/hardware-config.nix`                          | LUKS root/swap on A (`cryptroot`, `cryptswap`, `resumeDevice`), the `data` LUKS volume (`nofail`) at `/data`, the NTFS `/shared` mount and its pre-hibernation unmount, microcode, NPU, Bluetooth `KernelExperimental`, firmware set, `bolt`, `/data` ownership                                                                                                                                                                                                         |
| `modules/songbird/nvidia-gpu.nix`                               | `gpu.nvidia`: production branch, `open = true`, `vaapi.backend = "nvidia"`, `LIBVA_DRM_DEVICE=/dev/dri/by-path/pci-0000:02:00.0-render`, `metamode = "2560x1440_144"`, `nouveau` blacklisted; VRAM preservation across suspend comes from the shared module's `powerManagement.enable`                                                                                                                                                                                  |
| `modules/songbird/policy.nix`                                   | `sopsRuntimeReady` enabled; `r2RuntimeReady` remains off until Phase N2; required NVIDIA-host cache policy `cacheRoots.nvidiaKernelModules = false` keeps the source-built CachyOS module out of published cache roots; `duplicatiStateDirReadable`, `extraHomeApps`, empty `firewallDnsInterfaces`, TCP 8000-8999 restricted to IPv4 sources in `10.0.0.0/8` and `192.168.0.0/16`; TCP 9999 remains globally open through the shared baseline; primary handoff pending |
| `modules/songbird/firewall-policy-check.nix`                    | Flake check for exactly one source-scoped TCP 8000-8999 start and cleanup rule per approved CIDR, absence of overlapping source-unrestricted TCP ports or ranges, and the documented shared TCP 9999 state                                                                                                                                                                                                                                                              |
| `modules/songbird/services.nix`                                 | Samba media share (from `secrets/songbird.yaml`), on-demand `samba.target` with WS-Discovery bound to it, coredump retention, power-profiles-daemon forced to performance (replacing system76-power), cloudflared, WARP headless, LACT, system76-scheduler, printing off                                                                                                                                                                                                |
| `modules/songbird/imports.nix`                                  | Language toolchain enables only; no chassis modules                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `modules/songbird/networking.nix`                               | `.link` units for the two onboard NICs and the BE200 carrying no `Name=`: they displace `99-default.link` to drop its `mac` altname token without renaming. Pin a device by adding `Name=` to that same entry and dropping its `NamePolicy=`; a second `.link` for the same device is never read                                                                                                                                                                        |
| `modules/songbird/support.nix`                                  | `services.fwupd`                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `modules/songbird/apps-enable.nix`                              | Inkscape on; Logseq keeps GPU compositing (no PRIME here)                                                                                                                                                                                                                                                                                                                                                                                                               |
| `modules/songbird/gnome-keyring.nix`, `pass-secret-service.nix` | gnome-keyring off, `pass` as the secret service (as on system76)                                                                                                                                                                                                                                                                                                                                                                                                        |
| `modules/songbird/mpv.nix`                                      | `gpu-api = "opengl"` override; drop once Vulkan is verified on the 5080                                                                                                                                                                                                                                                                                                                                                                                                 |
| `modules/songbird/ssh.nix`                                      | `services.openssh.enable` override; public key pin pending (Phase N2 step 6)                                                                                                                                                                                                                                                                                                                                                                                            |
| `modules/songbird/host-id.nix`                                  | `networking.hostId = "c93b3b3c"`                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `modules/songbird/state-version.nix`                            | `system.stateVersion = "26.11"`                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `modules/songbird/nix-settings.nix`                             | `max-jobs = "auto"`, `max-substitution-jobs = 23` (`nproc - 1`), `min-free` 50 GB                                                                                                                                                                                                                                                                                                                                                                                       |
| `modules/songbird/r2-runtime.nix`                               | R2 runtime bindings gated on `r2RuntimeReady`                                                                                                                                                                                                                                                                                                                                                                                                                           |

`firewallDnsInterfaces` stays empty unless songbird actually serves DNS or
DHCP to the network: it opens inbound UDP 53/67 and TCP 53, and
NetworkManager's `dns = "dnsmasq"` mode does not count, since that dnsmasq
binds `127.0.0.1` and `::1` with no `dhcp-range`. If such a listener is ever
added, pin the intended NIC by adding `Name=` to its existing entry in
`modules/songbird/networking.nix` and dropping that entry's `NamePolicy=`, then
use the pinned name. Do not author a second `.link` for the device: udev applies
only the first matching file, so the new one is never read while `pinnedNamesOf`
still reads its `Name=` and reports the name as backed, which silences every
guard. The firewall checks also reject duplicate device-specific names and
broad or unbound files that precede another enabled `.link`. With
`net.ifnames=0` the two onboard NICs share the `eth0`/`eth1` pool by
discovery order, so neither name is bound to a device and the opening follows
whichever NIC the kernel enumerated first that boot.
`modules/hosts/common/firewall.nix` warns on an unpinned kernel name here, and
the warning goes quiet once a pin backs it. `docs/networking/README.md` covers
why such a pin has to land outside the kernel's own `eth*` namespace rather
than on `eth0` itself, and why the pin must omit `NamePolicy`.

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

| Item                        | State                                                                | Lands in                                                                 |
| --------------------------- | -------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| LUKS, ext4, ESP, swap UUIDs | Done (harvested)                                                     | `hardware-config.nix`                                                    |
| hostId                      | Done: `c93b3b3c`                                                     | `host-id.nix`                                                            |
| Wired interface names       | Done: `eth0` (RTL8126, uplink), `eth1` (I226-V) in enumeration order | Kernel `net.ifnames=0`, no pin                                           |
| Wi-Fi module vendor         | Done: Intel BE200 (`8086:272b`, iwlwifi)                             | `project-songbird.md`                                                    |
| Host SSH public key         | Done: pinned from `/etc/ssh/ssh_host_ed25519_key.pub`                | `ssh.nix` and `modules/hosts/common/ssh-known-hosts.nix`                 |
| age identity                | Done (installed and verified); `sopsRuntimeReady` enabled            | `/var/lib/sops-nix/key.txt`, `~/.config/sops/age/keys.txt`, `policy.nix` |
| Tailnet IPv4                | Pending `tailscale ip -4` after joining; carries the primary handoff | `policy.nix` `tailnetIp`, `primary`                                      |
| `/data` root key slot       | Added; the unattended initrd unlock is untested until a reboot       | LUKS header `183d1f98-…` (no repo change)                                |
| Windows disk                | Not decided                                                          | Phase N4                                                                 |
| Shared partition PARTUUID   | Only if Phase N5 converts W to BitLocker                             | `hardware-config.nix` crypttab entry                                     |
| BitLocker keys              | Windows BitLocker setup (Phases N4, N5)                              | Password manager; W password also to `/var/lib/secrets/shared-bitlk.key` |

## Validation Ladder

Per the runbook, before and after the PR. From the linked worktree
(`path:` forms; the plain `.` forms work in the primary checkout):

```sh
nix run path:.#treefmt -- .
nix flake check path:. --accept-flake-config --no-build --offline
nix build "path:.#nixosConfigurations.songbird.config.system.build.toplevel"
nix shell nixpkgs#git nixpkgs#nh -c ./build.sh -t songbird --boot   # from the worktree, on songbird; activates on next reboot
nix run path:.#generation-manager -- score   # target: 20/20
```

Plus host-specific checks after the first boot:

- `lsblk` shows `cryptroot`, `cryptswap`, `data` open; `findmnt /data /shared`.
- `nvidia-smi` reports the RTX 5080 on the open kernel module; `lsmod | grep nouveau` is empty.
- `ip -br link` shows `eth0`, `eth1`, `wlan0`; Wi-Fi and Bluetooth associate.
- `sensors` shows coretemp; `powerprofilesctl get` reports `performance`.
- Hibernate round-trip (`systemctl hibernate`) after confirming
  `boot.resumeDevice`; NVIDIA VRAM survives (decision 13).
- Assembly checklist Phase 7 load validation ran under the temporary Windows
  in Phase N0; re-spot-check on NixOS if wanted (`stress-ng`, `glmark2` are
  in the shared package set).

## Operating Rules (cross-OS)

1. Windows never hibernates and never fast-starts (`powercfg /h off`, Phase
   N4). This keeps B and W clean for every boot.
2. If NixOS is hibernated, resume NixOS. An image written with `/shared`
   mounted restores stale NTFS metadata over anything Windows wrote in
   between, which corrupts the volume silently, so
   `modules/songbird/hardware-config.nix` unmounts `/shared` from an
   `ExecStartPre` on `systemd-hibernate`, `systemd-hybrid-sleep` and
   `systemd-suspend-then-hibernate`, and remounts it from an `ExecStopPost`
   on the same units. `ExecStopPost` rather than `ExecStartPost` so the
   remount also runs when the transition itself fails; the unmount leaves a
   `/run/shared-remount-after-sleep` flag, so the remount touches only a
   `/shared` this host unmounted. A process holding `/shared` open makes the
   unmount fail, which aborts the hibernation rather than writing an unsafe
   image: close whatever holds it (`lsof /shared`) and retry. A remount that
   fails after resume leaves the sleep unit `failed`
   (`systemctl status systemd-hibernate`); a volume Windows left dirty is
   the usual cause, which rule 5 covers. Booting Windows after a clean NixOS
   shutdown or reboot is unaffected.
3. Windows feature updates may reorder UEFI boot entries. Fix is
   `efibootmgr -o` (or UEFI setup); they cannot damage A's ESP (decision 6).
4. BitLocker recovery keys and the W password live in the password manager;
   losing them makes B or W unrecoverable.
5. NixOS-side writes to `/shared` use the kernel ntfs3 driver with
   `windows_names`, which blocks file names Windows cannot read. A volume
   Windows left dirty refuses to mount; `nofail` lets the boot continue and
   `ntfsfix -d` (ntfs3g, in the shared app baseline) clears the flag.
6. Firmware updates (BIOS) reset boot order and can reset PTT: after any
   BIOS update, re-check boot order, Secure Boot off, and expect one
   BitLocker recovery-key prompt on Windows.

## TODO

- for nixos boot partition, it must be increased to at least 10GiB.
- rename /shared to /portal
- In windows, ensure that all the samsung SSDs and other are using up to date firmware, may require formatting.
- low priority: find a better way to manage boatloading, e.g. a separate new bootloader that allows for selecting moving to windows or nixos bootloader (bootchain..)
