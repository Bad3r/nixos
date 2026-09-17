# Songbird configuration

Songbird takes the hosts-common baseline through its registry entry in [registry.nix](../../modules/hosts/common/registry.nix); only non-obvious operational deviations follow.

## Boot and kernel

- The CachyOS kernel replaces the common zen kernel and is built locally with its NVIDIA module, so a kernel bump costs a local build: [cachyos-kernel.nix](../../modules/songbird/cachyos-kernel.nix).
- Hibernation resumes through the LUKS swap mapping: [hardware-config.nix](../../modules/songbird/hardware-config.nix).
- Intel microcode updates are pinned on, since the shared Intel CPU profile would otherwise derive them from the redistributable-firmware switch: [hardware-config.nix](../../modules/songbird/hardware-config.nix).
- The NPU at `0000:00:0b.0` gets its intel_vpu firmware and Level Zero driver, as `nixos-generate-config` reports for this CPU: [hardware-config.nix](../../modules/songbird/hardware-config.nix).

## GPU

- The NVIDIA driver runs its open kernel modules, since Blackwell is supported only by them: [nvidia-gpu.nix](../../modules/songbird/nvidia-gpu.nix).
- A fixed metamode pins the refresh rate, since the monitor advertises 60 Hz as preferred and RandR reverts to it on every hotplug and DPMS wake: [nvidia-gpu.nix](../../modules/songbird/nvidia-gpu.nix).
- mpv keeps the OpenGL backend under vo=gpu-next, since the Vulkan backend deadlocked the GPU on rapid playlist switching: [mpv.nix](../../modules/songbird/mpv.nix).
- The cache-root policy excludes songbird's NVIDIA kernel module from the binary cache, since it builds from source with no configured substituter: [policy.nix](../../modules/songbird/policy.nix).

## Storage

- The optional LUKS `/data` volume reuses the cached root passphrase, and its unlock is bounded so an absent device or unanswered prompt cannot block root: [hardware-config.nix](../../modules/songbird/hardware-config.nix).
- The `/portal` volume mounts through the ntfs3 driver, added to the supported filesystems, with nofail, Windows-safe names, and owner-only masks: [hardware-config.nix](../../modules/songbird/hardware-config.nix).
- `/portal` unmounts before hibernation and remounts after resume, since an image written with the volume mounted corrupts what Windows writes: [hardware-config.nix](../../modules/songbird/hardware-config.nix).

## Network

- Per-NIC and Wi-Fi `.link` units displace the default link policy so no MAC-derived altname exposes the factory address, and they pin no name, so eth0 and eth1 stay under kernel enumeration: [networking.nix](../../modules/songbird/networking.nix).
- A TCP range for local dev servers opens to LAN sources and on the Cloudflare Mesh interface, since Mesh counts as a local network: [policy.nix](../../modules/songbird/policy.nix).
- qBittorrent runs as a service inside the `torrent` network namespace, whose only route is a Proton VPN WireGuard tunnel, so a dropped tunnel leaves it no other way out: [qbittorrent.nix](../../modules/songbird/qbittorrent.nix).
- A renewal unit inside that namespace keeps Proton's NAT-PMP mapping alive and pushes the mapped port into the running session, since Proton assigns the port per tunnel session: [qbittorrent.nix](../../modules/songbird/qbittorrent.nix).
- The Web UI answers LAN and Mesh clients without a password through a socket proxy into the namespace: [qbittorrent.nix](../../modules/songbird/qbittorrent.nix).
- The Web UI port opens to LAN sources and on the Mesh interface through rules of its own, apart from the dev range: [qbittorrent.nix](../../modules/songbird/qbittorrent.nix).
- The `qbittorrent-webui` handler takes magnet links and `.torrent` files in place of the Qt client: [qbittorrent.nix](../../modules/songbird/qbittorrent.nix).
- The `nixos-songbird` WARP profile excludes the Proton endpoint, so the tunnel's outer packets leave through the wired uplink instead of riding the WARP tunnel: [deployment.md](../cloudflare/warp/deployment.md#change-a-profiles-exclude-list).

## Services

- A Samba media share renders from a host secret and starts only on demand; `openFirewall` opens its ports on every interface, so Samba's own `hosts allow` and `hosts deny` pair limits clients to loopback, the LAN, and Cloudflare Mesh: [services.nix](../../modules/songbird/services.nix).
- Samba WSDD runs beside it with its own `openFirewall`, opening TCP 5357 and UDP 3702 (WS-Discovery) on every interface as well: [services.nix](../../modules/songbird/services.nix).
- cloudflared runs as a tunnel service, beyond the CLI package the baseline installs: [services.nix](../../modules/songbird/services.nix).
- Cloudflare WARP enrolls with the host's service token in `warp` mode, so systemd-resolved sends every lookup to the WARP resolver while its tunnel is up, since nothing here serves private-host mappings: [cloudflare-warp.nix](../../modules/songbird/cloudflare-warp.nix).
- thermald stays off, since a desktop K-SKU under an AIO with BIOS Q-Fan curves gives it no platform to manage: [services.nix](../../modules/songbird/services.nix).
- fwupd is enabled, since LVFS covers firmware updates for the NVMe drives and USB peripherals: [support.nix](../../modules/songbird/support.nix).
- The power profile is forced to performance at boot and reasserted after resume through power-profiles-daemon, which drives the intel_pstate energy-performance preference: [services.nix](../../modules/songbird/services.nix).
- R2 sync units wait on the `/data` provisioning unit and run only while that volume stays mounted: [r2-runtime.nix](../../modules/songbird/r2-runtime.nix).
- `data-ownership.service` chowns `/data` to the owner, gated on the mount point rather than requiring it, so an absent volume leaves it inactive instead of failed and a hand mount has to start it explicitly: [hardware-config.nix](../../modules/songbird/hardware-config.nix).
- The power key locks the session and resume relocks it, since this desktop chassis has no lid switch to handle: [services.nix](../../modules/songbird/services.nix).
- Bluetooth turns on the kernel's experimental features for BLE battery reporting, on top of the controller the baseline enables: [hardware-config.nix](../../modules/songbird/hardware-config.nix).
- bolt authorizes Thunderbolt 4 and USB4 devices on the two rear ports: [hardware-config.nix](../../modules/songbird/hardware-config.nix).

## Policy

- The sops and R2 readiness gates turn on, unlocking secret-backed features once the age identity is installed: [policy.nix](../../modules/songbird/policy.nix).
