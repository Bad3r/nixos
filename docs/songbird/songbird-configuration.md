# Songbird configuration

Songbird takes the hosts-common baseline through its registry entry in [registry.nix](../../modules/hosts/common/registry.nix), and only what differs follows.

## Boot and kernel

- The CachyOS kernel replaces the common zen kernel and is built locally with its NVIDIA module, so a kernel bump costs a local build: [cachyos-kernel.nix](../../modules/songbird/cachyos-kernel.nix).
- Hibernation resumes through the LUKS swap mapping: [hardware-config.nix](../../modules/songbird/hardware-config.nix).
- Intel microcode updates are pinned on, since the shared Intel CPU profile would otherwise derive them from the redistributable-firmware switch: [hardware-config.nix](../../modules/songbird/hardware-config.nix).
- The NPU at `0000:00:0b.0` gets its intel_vpu firmware and Level Zero driver, as `nixos-generate-config` reports for this CPU: [hardware-config.nix](../../modules/songbird/hardware-config.nix).
- The firmware set is pinned to linux-firmware, sof-firmware, and wireless-regdb, matched to the drivers the stock install bound: [hardware-config.nix](../../modules/songbird/hardware-config.nix).

## GPU

- The NVIDIA driver runs its open kernel modules, since Blackwell is supported only by them: [nvidia-gpu.nix](../../modules/songbird/nvidia-gpu.nix).
- A fixed metamode pins the refresh rate, since the monitor advertises 60 Hz as preferred and RandR reverts to it on every hotplug and DPMS wake: [nvidia-gpu.nix](../../modules/songbird/nvidia-gpu.nix).
- mpv keeps the OpenGL backend under vo=gpu-next, since the Vulkan backend deadlocked the GPU on rapid playlist switching: [mpv.nix](../../modules/songbird/mpv.nix).
- The cache-root policy excludes songbird's NVIDIA kernel module from the binary cache, since it builds from source with no configured substituter: [policy.nix](../../modules/songbird/policy.nix).

## Storage

- Disk A carries the LUKS root and swap volumes: [hardware-config.nix](../../modules/songbird/hardware-config.nix).
- The optional LUKS `/data` volume reuses the cached root passphrase, and its unlock is bounded so an absent device or unanswered prompt cannot block root: [hardware-config.nix](../../modules/songbird/hardware-config.nix).
- The `/portal` volume mounts through the ntfs3 driver, added to the supported filesystems, with nofail, Windows-safe names, and owner-only masks: [hardware-config.nix](../../modules/songbird/hardware-config.nix).
- `/portal` unmounts before hibernation and remounts after resume, since an image written with the volume mounted corrupts what Windows writes: [hardware-config.nix](../../modules/songbird/hardware-config.nix).

## Network

- Per-NIC and Wi-Fi `.link` units displace the default link policy so no MAC-derived altname exposes the factory address, and they pin no name, so eth0 and eth1 stay under kernel enumeration: [networking.nix](../../modules/songbird/networking.nix).
- A TCP range for local dev servers opens, scoped to the LAN by the shared firewall helper: [policy.nix](../../modules/songbird/policy.nix).
- A host-only flake check approves the exact source-scoped rules that range generates, so a changed range or rule template fails `nix flake check` until the approved list follows: [firewall-policy-check.nix](../../modules/songbird/firewall-policy-check.nix).
- qBittorrent's incoming-peer port is open only on the Proton VPN tunnel interface, where Proton's NAT-PMP forwarding maps it: [qbittorrent.nix](../../modules/songbird/qbittorrent.nix).

## Services

- A Samba media share renders from a host secret and starts only on demand; `openFirewall` opens 139/445 on every interface, so the LAN restriction is Samba's own `hosts allow` and `hosts deny` pair, not a firewall scope: [services.nix](../../modules/songbird/services.nix).
- Samba WSDD runs beside it with its own `openFirewall`, opening the WS-Discovery ports on every interface as well: [services.nix](../../modules/songbird/services.nix).
- Coredump retention adds a local time bound on top of the shared baseline: [services.nix](../../modules/songbird/services.nix).
- cloudflared runs as a tunnel service, beyond the CLI package the baseline installs: [services.nix](../../modules/songbird/services.nix).
- Cloudflare WARP runs headless as a service, beyond the CLI package the baseline installs: [services.nix](../../modules/songbird/services.nix).
- LACT enables GPU control and monitoring over NVML: [services.nix](../../modules/songbird/services.nix).
- Printing is forced off: [services.nix](../../modules/songbird/services.nix).
- thermald stays off, since a desktop K-SKU under an AIO with BIOS Q-Fan curves gives it no platform to manage: [services.nix](../../modules/songbird/services.nix).
- fwupd is enabled, since LVFS covers firmware updates for the NVMe drives and USB peripherals: [support.nix](../../modules/songbird/support.nix).
- The power profile is forced to performance at boot and reasserted after resume through power-profiles-daemon, which drives the intel_pstate energy-performance preference: [services.nix](../../modules/songbird/services.nix).
- R2 sync units wait on the `/data` provisioning unit and run only while that volume stays mounted: [r2-runtime.nix](../../modules/songbird/r2-runtime.nix).
- `data-ownership.service` chowns `/data` to the owner, gated on the mount point rather than requiring it, so an absent volume leaves it inactive instead of failed and a hand mount has to start it explicitly: [hardware-config.nix](../../modules/songbird/hardware-config.nix).
- The power key locks the session and resume relocks it, since this desktop chassis has no lid switch to handle: [services.nix](../../modules/songbird/services.nix).
- Bluetooth turns on the kernel's experimental features for BLE battery reporting, on top of the controller the baseline enables: [hardware-config.nix](../../modules/songbird/hardware-config.nix).
- bolt authorizes Thunderbolt 4 and USB4 devices on the two rear ports: [hardware-config.nix](../../modules/songbird/hardware-config.nix).
- Claude Code installs through bun at activation, which needs the npm registry reachable: [apps-enable.nix](../../modules/songbird/apps-enable.nix).
- Inkscape is on: [apps-enable.nix](../../modules/songbird/apps-enable.nix).
- The Clojure, Rust, Java, Python, and Go extended language sets are on: [imports.nix](../../modules/songbird/imports.nix).

## Policy

- gnome-keyring is forced off: [gnome-keyring.nix](../../modules/songbird/gnome-keyring.nix).
- pass backs the desktop secret-service portal instead: [pass-secret-service.nix](../../modules/songbird/pass-secret-service.nix).
- Songbird is marked the primary fleet endpoint, so `programs.tailscale.extended.sshHostName` in [tailscale.nix](../../modules/apps/tailscale.nix) defaults its generated `~/.ssh/hosts` alias to songbird's tailnet address: [policy.nix](../../modules/songbird/policy.nix).
- The sops and R2 readiness gates turn on, unlocking secret-backed features once the age identity is installed: [policy.nix](../../modules/songbird/policy.nix).
- awscli2 and the pentesting devshell join the Home Manager app set: [policy.nix](../../modules/songbird/policy.nix).
- The owner can read the duplicati-r2 state directory: [policy.nix](../../modules/songbird/policy.nix).
- Nix settings pin songbird's parallel build-job count, substitution-job concurrency, and a minimum free-space threshold for garbage collection: [nix-settings.nix](../../modules/songbird/nix-settings.nix).
- Songbird pins its own host id, system state version, and SSH host key as install-time constants: [host-id.nix](../../modules/songbird/host-id.nix), [state-version.nix](../../modules/songbird/state-version.nix), and [ssh.nix](../../modules/songbird/ssh.nix).
