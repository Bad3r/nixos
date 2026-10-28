# Host File Inventory

NixOS fragments under `modules/hosts/<host>/` extend `configurations.nixos.<host>.module`, while `policy.nix` contributes per-host registry data.
Cross-host concerns live under `modules/hosts/common/`; a host directory carries hardware truth, chassis-specific modules, and small value files.
Run `ls modules/hosts/<host>/` to audit a host's files.

Every host needs an explicit `shareCommon` entry in `modules/hosts/common/registry.nix`.
The host constructor aborts evaluation without one, so common-baseline participation is always a recorded choice: `true` opts in and `false` opts out.
The full procedure lives in the [host onboarding runbook](../guides/host-onboarding.md).

## Songbird

Songbird is the managed-workstation instance of the host directory pattern.

| File                                           | Purpose                                                                                                                                                                                                                            |
| ---------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `modules/hosts/songbird/nix-settings.nix`      | Hardware-tuned `max-jobs`, `max-substitution-jobs` (`nproc - 1`), and `min-free` overrides                                                                                                                                         |
| `modules/hosts/songbird/ssh.nix`               | Explicit OpenSSH enable choice and host public key, matched against `fleetHostKeys` at evaluation                                                                                                                                  |
| `modules/hosts/songbird/r2-runtime.nix`        | Host runtime bindings for external `r2-flake` modules, gated on the `r2RuntimeReady` registry flag                                                                                                                                 |
| `modules/hosts/songbird/hardware-config.nix`   | LUKS root and swap on the SN8100, the `/data` LUKS+XFS volume, firmware, NPU, Thunderbolt (bolt)                                                                                                                                   |
| `modules/hosts/songbird/host-id.nix`           | `networking.hostId`                                                                                                                                                                                                                |
| `modules/hosts/songbird/state-version.nix`     | Install-time `system.stateVersion` constant (`26.11`)                                                                                                                                                                              |
| `modules/hosts/songbird/support.nix`           | `services.fwupd` (LVFS); no vendor daemon on this board                                                                                                                                                                            |
| `modules/hosts/songbird/nvidia-gpu.nix`        | GPU profile over `flake.nixosModules.nvidia-gpu`: production branch, open kernel modules (Blackwell), NVDEC VA-API through nvidia-vaapi-driver, intel-media-driver for apps on the iGPU                                            |
| `modules/hosts/songbird/mpv.nix`               | mpv `gpu-api = "opengl"` override for reliable RTX 5080 playback                                                                                                                                                                   |
| `modules/hosts/songbird/qbittorrent.nix`       | qBittorrent service in the `torrent` network namespace behind a Proton VPN WireGuard tunnel, with NAT-PMP port renewal and a Web UI proxy for LAN and Mesh clients                                                                 |
| `modules/hosts/songbird/qbittorrent-webui.nix` | Desktop handler enable and the patched copy of the service's own Web UI, served in place of its built-in one                                                                                                                       |
| `modules/hosts/songbird/apps-enable.nix`       | Per-host overrides over the common app baseline                                                                                                                                                                                    |
| `modules/hosts/songbird/cloudflare-warp.nix`   | WARP `serviceMode = "warp"`: systemd-resolved sends every lookup to the WARP resolver while its tunnel is up                                                                                                                       |
| `modules/hosts/songbird/policy.nix`            | Registry data under `flake.lib.nixos.hosts.songbird` (readiness gates and per-host values)                                                                                                                                         |
| `modules/hosts/songbird/services.nix`          | Host-divergent services                                                                                                                                                                                                            |
| `modules/hosts/songbird/fonts.nix`             | Arabic fontconfig rules through the `host.fontconfig.extraRules` option                                                                                                                                                            |
| `modules/hosts/songbird/networking.nix`        | `.link` units for the two onboard NICs and the BE200 carrying no `Name=`: they displace `99-default.link` to drop its `mac` altname token without renaming                                                                         |
| `modules/hosts/songbird/workloads.nix`         | Declared workload networks, guests, and staged media; `policy.nix` holds the network registry ids                                                                                                                                  |
| `modules/hosts/songbird/cachyos-kernel.nix`    | Pinned CachyOS overlay and `boot.kernelPackages` override over the common `linuxPackages_zen` default; the kernel and its NVIDIA module are built locally, which is why `policy.nix` sets `cacheRoots.nvidiaKernelModules = false` |

## Shared Boundaries

Cross-host baselines live in `modules/hosts/common/` and contribute to `flake.nixosModules.hosts-common`.
The host constructor imports that aggregate before each host-specific module when `flake.lib.nixos.hosts.<host>.shareCommon = true`.
Host-specific modules can disable a storage-dependent baseline when the hardware lacks its required mount.

General Nix daemon and evaluator settings live in `modules/base/nix-settings.nix`.
The common `nix-substituters` module owns substitution settings only, and reads cache topology and download retry values from `.github/actions/install-lix/substituters.conf`.
Per-host `nix-settings.nix` files stay limited to hardware-tuned values such as `max-jobs`, `max-substitution-jobs` (`nproc - 1`), and `min-free`.
