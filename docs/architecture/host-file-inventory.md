# Host File Inventory

NixOS fragments under `modules/<host>/` extend `configurations.nixos.<host>.module`, while `policy.nix` contributes per-host registry data.
Cross-host concerns live under `modules/hosts/common/`; a host directory carries hardware truth, chassis-specific modules, and small value files.
Run `ls modules/<host>/` to audit a host's files.

Every host needs an explicit `shareCommon` entry in `modules/hosts/common/registry.nix`.
The host constructor aborts evaluation without one, so common-baseline participation is always a recorded choice: `true` opts in and `false` opts out.
The full procedure lives in the [host onboarding runbook](../guides/host-onboarding.md).

## Songbird

Songbird is the managed-workstation instance of the host directory pattern.

| File                                         | Purpose                                                                                                                                                                                                                            |
| -------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `modules/songbird/imports.nix`               | Language toolchain enables only; the desktop board has no vendor module, so nothing chassis-specific to import                                                                                                                     |
| `modules/songbird/nix-settings.nix`          | Hardware-tuned `max-jobs`, `max-substitution-jobs` (`nproc - 1`), and `min-free` overrides                                                                                                                                         |
| `modules/songbird/ssh.nix`                   | Explicit OpenSSH enable choice and host public key for its known-hosts entry and fleet-key parity check                                                                                                                            |
| `modules/songbird/r2-runtime.nix`            | Host runtime bindings for external `r2-flake` modules, gated on the `r2RuntimeReady` registry flag                                                                                                                                 |
| `modules/songbird/hardware-config.nix`       | LUKS root and swap on the SN8100, the `/data` LUKS+XFS volume, firmware, NPU, Thunderbolt (bolt)                                                                                                                                   |
| `modules/songbird/host-id.nix`               | `networking.hostId`                                                                                                                                                                                                                |
| `modules/songbird/state-version.nix`         | Install-time `system.stateVersion` constant (`26.11`)                                                                                                                                                                              |
| `modules/songbird/support.nix`               | `services.fwupd` (LVFS); no vendor daemon on this board                                                                                                                                                                            |
| `modules/songbird/nvidia-gpu.nix`            | GPU profile over `flake.nixosModules.nvidia-gpu`: production branch, open kernel modules (Blackwell), NVDEC VA-API through nvidia-vaapi-driver, `2560x1440_144` metamode                                                           |
| `modules/songbird/mpv.nix`                   | mpv `gpu-api = "opengl"` override for reliable RTX 5080 playback                                                                                                                                                                   |
| `modules/songbird/gnome-keyring.nix`         | gnome-keyring force-disabled in favor of the `pass` secret service                                                                                                                                                                 |
| `modules/songbird/pass-secret-service.nix`   | DBus secret-service for `pass`                                                                                                                                                                                                     |
| `modules/songbird/qbittorrent.nix`           | qBittorrent incoming-peer port TCP+UDP 48845, opened only on the `proton0` Proton VPN tunnel interface                                                                                                                             |
| `modules/songbird/apps-enable.nix`           | Per-host overrides over the common app baseline (Inkscape on)                                                                                                                                                                      |
| `modules/songbird/policy.nix`                | Registry data under `flake.lib.nixos.hosts.songbird` (`primary`, `tailnetIp`, readiness gates, per-host values)                                                                                                                    |
| `modules/songbird/services.nix`              | Host-divergent services (Samba media share, power-profiles-daemon performance profile, cloudflared, WARP, LACT)                                                                                                                    |
| `modules/songbird/networking.nix`            | `.link` units for the two onboard NICs and the BE200 carrying no `Name=`: they displace `99-default.link` to drop its `mac` altname token without renaming                                                                         |
| `modules/songbird/cachyos-kernel.nix`        | Pinned CachyOS overlay and `boot.kernelPackages` override over the common `linuxPackages_zen` default; the kernel and its NVIDIA module are built locally, which is why `policy.nix` sets `cacheRoots.nvidiaKernelModules = false` |
| `modules/songbird/firewall-policy-check.nix` | Flake check `songbird-firewall-port-policy`: exactly one source-scoped start and cleanup rule per declared TCP range per approved CIDR, no source-unrestricted overlap, and TCP 9999 still globally open                           |

## Tpnix

| File                                     | Purpose                                                                                                                                                          |
| ---------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `modules/tpnix/apps-enable.nix`          | Per-host overrides over the common app baseline                                                                                                                  |
| `modules/tpnix/default-apps.nix`         | Per-host overrides for `host.defaults` (audioPlayer, videoPlayer = null)                                                                                         |
| `modules/tpnix/nix-settings.nix`         | Hardware-tuned `max-jobs`, `max-substitution-jobs` (`nproc - 1`), and `min-free` overrides                                                                       |
| `modules/tpnix/ssh.nix`                  | Explicit OpenSSH enable choice and host public key                                                                                                               |
| `modules/tpnix/firmware-manager-fix.nix` | tpnix-only `services.fwupd.enable = true;` override                                                                                                              |
| `modules/tpnix/fingerprint.nix`          | Fingerprint auth (`services.fprintd`) and PAM service wiring (tpnix-only)                                                                                        |
| `modules/tpnix/fonts.nix`                | Arabic fontconfig rules through the `host.fontconfig.extraRules` option                                                                                          |
| `modules/tpnix/gnome-keyring.nix`        | gnome-keyring with login, LightDM, and LightDM autologin PAM integration; conditional GNOME polkit agent                                                         |
| `modules/tpnix/networking.nix`           | `.link` unit pinning the internal Wi-Fi card to `wifi0` by PCI path                                                                                              |
| `modules/tpnix/printing.nix`             | Printer provisioning with a SOPS-managed device URI (tpnix-only)                                                                                                 |
| `modules/tpnix/r2-runtime.nix`           | Host runtime bindings for external `r2-flake` modules, gated on the `r2RuntimeReady` registry flag                                                               |
| `modules/tpnix/hardware-config.nix`      | Filesystems, firmware, loader entry limit, low-level hardware settings                                                                                           |
| `modules/tpnix/host-id.nix`              | `networking.hostId`                                                                                                                                              |
| `modules/tpnix/state-version.nix`        | Install-time `system.stateVersion` constant                                                                                                                      |
| `modules/tpnix/support.nix`              | Stub for future tpnix hardware-support hooks                                                                                                                     |
| `modules/tpnix/policy.nix`               | Registry data under `flake.lib.nixos.hosts.tpnix` (readiness gates, per-host values, private DNS host secret keys)                                               |
| `modules/tpnix/power.nix`                | GPU profile over `flake.nixosModules.nvidia-gpu` plus display and power services (`power-profiles-daemon`, logind lid handling)                                  |
| `modules/tpnix/services.nix`             | Host-divergent services (printing, power-profiles-daemon stack, espanso X11 override)                                                                            |
| `modules/tpnix/ssh-private-host.nix`     | SOPS-backed SSH config at `~/.ssh/hosts/private-host` and public key at `~/.ssh/private-host-identity.pub`, gated on `sopsRuntimeReady` and `secrets/tpnix.yaml` |

## Shared Boundaries

Cross-host baselines live in `modules/hosts/common/` and contribute to `flake.nixosModules.hosts-common`.
The host constructor imports that aggregate before each host-specific module when `flake.lib.nixos.hosts.<host>.shareCommon = true`.
Host-specific modules can disable a storage-dependent baseline when the hardware lacks its required mount.

General Nix daemon and evaluator settings live in `modules/base/nix-settings.nix`.
The common `nix-substituters` module owns cache topology and download retry settings only.
Per-host `nix-settings.nix` files stay limited to hardware-tuned values such as `max-jobs`, `max-substitution-jobs` (`nproc - 1`), and `min-free`.
