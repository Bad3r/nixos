# tpnix Hardware Migration Plan

Status: current
Target host: `tpnix` on Lenovo ThinkPad P15s Gen 2i
Goal: keep `tpnix` as the canonical host identity while replacing the old hardware profile with the scanned facts from this device.

## 1) Current Hardware Facts

- Machine model: Lenovo ThinkPad P15s Gen 2i
- Platform: `x86_64-linux`
- Boot mode: EFI with `systemd-boot`
- Root filesystem:
  - mapped device: `/dev/mapper/luks-dc8e394e-d685-429e-b256-3b803635b47d`
  - backing LUKS UUID: `dc8e394e-d685-429e-b256-3b803635b47d`
  - filesystem: `ext4`
- Boot filesystem:
  - device UUID: `1F94-C5D7`
  - filesystem: `vfat`
- Swap:
  - mapped device: `/dev/mapper/luks-df7db70f-8965-4516-976d-8fdac91ae660`
  - backing LUKS UUID: `df7db70f-8965-4516-976d-8fdac91ae660`
- Required initrd modules:
  - `xhci_pci`
  - `thunderbolt`
  - `nvme`
  - `usbhid`
  - `usb_storage`
  - `sd_mod`
  - `sdhci_pci`
- Required kernel modules:
  - `kvm-intel`

These values come from the locally generated `/etc/nixos/hardware-configuration.nix` and supersede the old unencrypted `tpnix` storage layout.

## 2) Module Ownership

- `modules/tpnix/hardware-config.nix` owns all scan-derived facts:
  - `boot.initrd.availableKernelModules`
  - `boot.initrd.kernelModules`
  - `boot.initrd.luks.devices`
  - `boot.kernelModules`
  - `boot.extraModulePackages`
  - `fileSystems`
  - `swapDevices`
- `modules/tpnix/boot.nix` owns host policy:
  - `pkgs.cachyosKernels.linuxPackages-cachyos-latest`
  - `systemd-boot` settings
  - crash dump reservation
  - kernel sysctls
- `modules/tpnix/firmware-manager-fix.nix` owns the firmware-manager compatibility override and enables `services.fwupd`.
- The repo keeps using `modules/base/hardware-scan.nix` for generic scan support. Do not import `installer/scan/not-detected.nix` directly into the host module.

## 3) Migration Requirements

- Preserve logical identity:
  - keep `networking.hostName = "tpnix"`
  - keep single user `vx`
- Rotate physical-machine identity:
  - set a new random `networking.hostId`
  - expect new SSH host keys on the replacement hardware
- Keep this branch scoped to the hardware baseline:
  - current-storage facts
  - host identity rotation
  - bootloader policy
  - firmware update support
- Use the host boot policy that is actually committed here:
  - `boot.kernelPackages = lib.mkDefault pkgs.cachyosKernels.linuxPackages-cachyos-latest`
  - `systemd-boot` stays enabled with the existing editor, console, and configuration-limit settings
- Keep the graphics-stack migration out of scope for this document revision:
  - do not describe `NVIDIA PRIME`, `services.xserver.videoDrivers`, or runtime graphics policy here
- Keep existing touchpad behavior unless validation shows a regression:
  - tap-to-click
  - middle-button emulation
  - natural scrolling
- Keep power and desktop policy unchanged where still valid:
  - `power-profiles-daemon`
  - `thermald`
  - `NetworkManager`
  - Bluetooth enabled
  - lid close suspends

## 4) Pitfalls To Avoid

- Do not reuse the old plain ext4 root, EFI, or swap UUIDs; the new host uses encrypted root and encrypted swap.
- Do not leave boot storage facts split across `boot.nix` and `hardware-config.nix`; that creates drift on the next hardware change.
- Do not copy the generated file verbatim into the repo; preserve repo policy and only lift the machine-specific facts.
- Do not reuse the old `networking.hostId`; that risks collisions if the previous machine ever comes back online.
- Do not let this document describe a different kernel or graphics policy than the code in this branch; this branch now carries the CachyOS boot policy and leaves the graphics stack to a separate change.
- Do not assume missing firmware packages in advance. If Wi-Fi, audio, or suspend behavior fails after boot, inspect logs and add only the exact firmware that is proven necessary.

## 5) Validation And Rollout

- Validate from the repo root:
  1. `nix flake check --accept-flake-config --no-build --offline`
  2. `nix build .#nixosConfigurations.tpnix.config.system.build.toplevel`
- Deploy cautiously:
  1. `./build.sh --host tpnix --boot`
  2. reboot into the generated `tpnix` entry
- First-boot acceptance checks:
  1. `hostnamectl` reports `tpnix`
  2. `findmnt / /boot` shows the mapped LUKS root and the new EFI UUID
  3. `swapon --show` shows the mapped encrypted swap device
  4. boot unlock prompts work cleanly with reused LUKS passphrases
  5. `bootctl status` is healthy
  6. Wi-Fi, Bluetooth, audio, suspend/resume, touchpad, and external display paths work
  7. SSH clients have the new host key recorded for `tpnix`
