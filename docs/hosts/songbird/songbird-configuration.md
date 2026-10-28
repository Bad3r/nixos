# Songbird configuration

Songbird takes the hosts-common baseline through its registry entry in [registry.nix](../../../modules/hosts/common/registry.nix); only non-obvious operational deviations follow.

## Boot and kernel

- The CachyOS kernel replaces the common zen kernel and is built locally with its NVIDIA module, so a kernel bump costs a local build: [cachyos-kernel.nix](../../../modules/hosts/songbird/cachyos-kernel.nix).
- Hibernation resumes through the LUKS swap mapping: [hardware-config.nix](../../../modules/hosts/songbird/hardware-config.nix).
- Intel microcode updates are pinned on, since the shared Intel CPU profile would otherwise derive them from the redistributable-firmware switch: [hardware-config.nix](../../../modules/hosts/songbird/hardware-config.nix).
- The NPU at `0000:00:0b.0` gets its intel_vpu firmware and Level Zero driver, as `nixos-generate-config` reports for this CPU: [hardware-config.nix](../../../modules/hosts/songbird/hardware-config.nix).

## GPU

- The NVIDIA driver runs its open kernel modules, since Blackwell is supported only by them: [nvidia-gpu.nix](../../../modules/hosts/songbird/nvidia-gpu.nix).
- libva carries the iGPU's driver beside nvidia-vaapi-driver, so an app can select the iGPU in its own wrapper while the session stays on NVDEC: [nvidia-gpu.nix](../../../modules/hosts/songbird/nvidia-gpu.nix).
- The monitor advertises a low refresh rate as preferred. The i3 display handler selects the highest advertised rate at the preferred resolution on startup and reconnect: [services.nix](../../../modules/apps/i3wm/services.nix).
- RustDesk encodes the shared screen as H.264 or H.265 on the iGPU through VA-API, keeping NVENC off the RTX 5080 that runs llama.cpp: [rustdesk.nix](../../../modules/hosts/songbird/rustdesk.nix).
- mpv keeps the OpenGL backend under vo=gpu-next, since the Vulkan backend deadlocked the GPU on rapid playlist switching: [mpv.nix](../../../modules/hosts/songbird/mpv.nix).
- The cache-root policy excludes songbird's NVIDIA kernel module from the binary cache, since it builds from source with no configured substituter: [policy.nix](../../../modules/hosts/songbird/policy.nix).

## Storage

- The optional LUKS `/data` volume reuses the cached root passphrase, and its unlock is bounded so an absent device or unanswered prompt cannot block root: [hardware-config.nix](../../../modules/hosts/songbird/hardware-config.nix).
- The `/portal` volume mounts through the ntfs3 driver, added to the supported filesystems, with nofail, Windows-safe names, and owner-only masks: [hardware-config.nix](../../../modules/hosts/songbird/hardware-config.nix).
- `/portal` unmounts before hibernation and remounts after resume, since an image written with the volume mounted corrupts what Windows writes: [hardware-config.nix](../../../modules/hosts/songbird/hardware-config.nix).

## Network

- Private SSH aliases and their 1Password public identity render through user SOPS, keeping connection details encrypted: [ssh-private-host.nix](../../../modules/hosts/songbird/ssh-private-host.nix).
- Per-NIC and Wi-Fi `.link` units displace the default link policy so no MAC-derived altname exposes the factory address, and they pin no name, so eth0 and eth1 stay under kernel enumeration: [networking.nix](../../../modules/hosts/songbird/networking.nix).
- A TCP range for local dev servers opens to LAN sources and on the Cloudflare Mesh interface, since Mesh counts as a local network: [policy.nix](../../../modules/hosts/songbird/policy.nix).
- qBittorrent runs as a service inside the `torrent` network namespace, whose only route is a Proton VPN WireGuard tunnel, so a dropped tunnel leaves it no other way out: [qbittorrent.nix](../../../modules/hosts/songbird/qbittorrent.nix).
- That service runs as the `qbittorrent` system user, so an abused Web UI reaches only the profile and the save roots: [qbittorrent.nix](../../../modules/hosts/songbird/qbittorrent.nix).
- ACLs on every tree in `saveRoots` let the service write any folder under it while the owner keeps full access: [qbittorrent.nix](../../../modules/hosts/songbird/qbittorrent.nix).
- Every path but the store is noexec inside the service, so nothing it downloads or writes can run: [qbittorrent.nix](../../../modules/hosts/songbird/qbittorrent.nix).
- A renewal unit inside that namespace keeps Proton's NAT-PMP mapping alive and pushes the mapped port into the running session, since Proton assigns the port per tunnel session: [qbittorrent.nix](../../../modules/hosts/songbird/qbittorrent.nix).
- The Web UI answers LAN and Mesh clients without a password through a socket proxy into the namespace: [qbittorrent.nix](../../../modules/hosts/songbird/qbittorrent.nix).
- The Web UI port opens to LAN sources and on the Mesh interface through rules of its own, apart from the dev range: [qbittorrent.nix](../../../modules/hosts/songbird/qbittorrent.nix).
- The `qbittorrent-webui` handler takes magnet links and `.torrent` files in place of the Qt client: [qbittorrent-webui.nix](../../../modules/hosts/songbird/qbittorrent-webui.nix).
- The service serves a patched copy of its stock Web UI, so a link opens straight in the add dialog: [qbittorrent-webui.nix](../../../modules/hosts/songbird/qbittorrent-webui.nix).
- A duplicate already in the transfer list gets a prompt to merge trackers, as the desktop client does: [qbittorrent-webui.nix](../../../modules/hosts/songbird/qbittorrent-webui.nix).
- The handler's tab closes once its add dialogs finish: [qbittorrent-webui.nix](../../../modules/hosts/songbird/qbittorrent-webui.nix).
- The Proton endpoint stays inside the WARP tunnel and `wg-torrent` carries an MTU sized for it, because the ISP drops a WireGuard flow it can see: [qbittorrent.nix](../../../modules/hosts/songbird/qbittorrent.nix).
- virt-manager guests land on a declared `default` workload network that replaces libvirt's stock one, leaves only through WARP, and isolates guests from each other: [workloads.nix](../../../modules/hosts/songbird/workloads.nix).
- Declared trusted guests share a `desktop` workload network that leaves only through WARP: [workloads.nix](../../../modules/hosts/songbird/workloads.nix).

## Services

- A Samba media share renders from a host secret and starts only on demand; `openFirewall` opens its ports on every interface, so Samba's own `hosts allow` and `hosts deny` pair limits clients to loopback, the LAN, and Cloudflare Mesh: [services.nix](../../../modules/hosts/songbird/services.nix).
- Samba WSDD runs beside it with its own `openFirewall`, opening TCP 5357 and UDP 3702 (WS-Discovery) on every interface as well: [services.nix](../../../modules/hosts/songbird/services.nix).
- The fleet's RustDesk ID server and relay run here on the Mesh interface alone, so no device needs RustDesk's public servers, and a session that cannot connect directly falls back to the relay: [rustdesk/nixos.nix](../../../modules/apps/rustdesk/nixos.nix).
- cloudflared runs as a tunnel service, beyond the CLI package the baseline installs: [services.nix](../../../modules/hosts/songbird/services.nix).
- llama.cpp serves local models from a system service that starts at boot, listening on every interface with its port open to the LAN and the Mesh, since every model request needs the sops API key: [services.nix](../../../modules/hosts/songbird/services.nix).
- paperless-ngx serves its web UI on every interface with its port open to the LAN and the Mesh, behind its own login: [services.nix](../../../modules/hosts/songbird/services.nix).
- Its web and task-queue units, Tika, and Gotenberg pass IP traffic only to and from loopback, the web UI adding the LAN and Mesh ranges, so a compromised document parser reaches nothing outside the host: [paperless.nix](../../../modules/apps/paperless.nix).
- Its database and indexes stay on the root disk, while documents, the inbox, and the nightly export live under `/data/paperless`, so its units require the `/data` mount: [services.nix](../../../modules/hosts/songbird/services.nix).
- An ACL gives the owner alone write access to the inbox, and its default entries let paperless read whatever the owner creates there: [services.nix](../../../modules/hosts/songbird/services.nix).
- The nightly export joins the `r2-restic` backup paths, and an ACL lets the owner, as whom the backup runs, read the exported files: [services.nix](../../../modules/hosts/songbird/services.nix).
- Cloudflare WARP enrolls with the host's service token in `warp` mode, so systemd-resolved sends every lookup to the WARP resolver while its tunnel is up: [cloudflare-warp.nix](../../../modules/hosts/songbird/cloudflare-warp.nix).
- thermald stays off, since a desktop K-SKU under an AIO with BIOS Q-Fan curves gives it no platform to manage: [services.nix](../../../modules/hosts/songbird/services.nix).
- fwupd is enabled, since LVFS covers firmware updates for the NVMe drives and USB peripherals: [support.nix](../../../modules/hosts/songbird/support.nix).
- The power profile is forced to performance at boot and reasserted after resume through power-profiles-daemon, which drives the intel_pstate energy-performance preference: [services.nix](../../../modules/hosts/songbird/services.nix).
- R2 sync units wait on the `/data` provisioning unit and run only while that volume stays mounted: [r2-runtime.nix](../../../modules/hosts/songbird/r2-runtime.nix).
- User timers run `git maintenance` on the nixpkgs fork clone and fail while `/data` is unmounted, since `git for-each-repo` rejects a missing path: [git-maintenance.nix](../../../modules/hosts/songbird/git-maintenance.nix).
- `data-ownership.service` chowns `/data` to the owner, gated on the mount point rather than requiring it, so an absent volume leaves it inactive instead of failed and a hand mount has to start it explicitly: [hardware-config.nix](../../../modules/hosts/songbird/hardware-config.nix).
- The power key locks the session and resume relocks it, since this desktop chassis has no lid switch to handle: [services.nix](../../../modules/hosts/songbird/services.nix).
- Bluetooth turns on the kernel's experimental features for BLE battery reporting, on top of the controller the baseline enables: [hardware-config.nix](../../../modules/hosts/songbird/hardware-config.nix).
- bolt authorizes Thunderbolt 4 and USB4 devices on the two rear ports: [hardware-config.nix](../../../modules/hosts/songbird/hardware-config.nix).

## Policy

- The sops and R2 readiness gates turn on, unlocking secret-backed features once the age identity is installed: [policy.nix](../../../modules/hosts/songbird/policy.nix).
