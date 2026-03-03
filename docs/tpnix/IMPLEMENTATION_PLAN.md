# tpnix Technical Implementation Plan

Status: draft  
Target host: `tpnix` (new office laptop, 8 GiB RAM, single user `vx`)  
Goal: add a lean NixOS configuration alongside `system76` using the existing flake structure and minimal hardware changes (reuse current partitions; no new encryption/repartitioning).

## 1) Objectives & Constraints

- Lightweight, “office/CLI-first” profile: i3wm, terminal, browsers, file manager, note/office tools; no gaming/pentest/virtualization/heavy SDKs by default.
- Keep current disk layout and encryption as-is; reuse `/etc/nixos/hardware-configuration.nix` data.
- Maintain single user `vx`; repo now supports multiple hosts (`system76`, `tpnix`).
- Prefer upstream kernels and generic hardware settings; avoid System76/NVIDIA/CachyOS specifics unless detected hardware requires it.

## 2) Inputs & Facts

- Hardware (from `/etc/nixos/hardware-configuration.nix`):
  - `/` UUID `11920378-b861-46d6-b4d8-64a90ce03bbb` (ext4)
  - `/boot` UUID `DC64-2E36` (vfat, fmask/dmask 0077)
  - swap UUID `a9baee3b-5b98-4a80-95c9-0c1cb974b2e9`
  - initrd modules: `xhci_pci thunderbolt nvme usb_storage sd_mod`; kernelModules: `kvm-intel`; hostPlatform `x86_64-linux`; intel microcode enabled.
- System style: flake-parts auto-import; `configurations.nixos.<host>.module` pattern; apps via `modules/apps` + app toggles.
- Secrets: `sops-nix` key at `/var/lib/sops-nix/key.txt`; MonoLisa font secret optional.

## 3) Target Host Topology

- New aggregator module: `modules/tpnix/imports.nix`
  - Imports shared: `flake.nixosModules.{base,lang,ssh}` (and other shared modules still applicable: xdg, pipewire, dbus, nix-settings as host scope).
  - Omits System76-specific imports and CachyOS kernel overlay.
  - Exposes `flake.nixosConfigurations.tpnix`.
- Host-specific modules under `modules/tpnix/`:
  - `hardware-config.nix` (from current `/etc/nixos/hardware-configuration.nix`, plus touchpad tweaks).
  - `hostname.nix` (`networking.hostName = "tpnix"`).
  - `host-id.nix` (new random 8-hex).
  - `network.nix` (NetworkManager, firewall minimal: allow ssh 22 only unless needed).
  - `nix-settings.nix` (experimental features, lower `min-free` ~8–10 GiB, `max-jobs` 2–4, `auto-optimise-store = true`; optional `nix-substituters` reuse).
  - `state-version.nix` (`26.05`).
  - `power.nix` (enable `power-profiles-daemon`; disable system76-scheduler/lact).
  - `apps-enable.nix` (lean app profile; see §5).
  - `default-apps.nix` override (align defaults to enabled apps).
  - Optional: `fonts.nix` (reuse MonoLisa if secret present), `nix-ld.nix` (only if needed for FHS/VSC).

## 4) Hardware & Boot Plan

- Use stock `pkgs.linuxPackages`.
- Keep initrd modules and swap/root/boot UUIDs exactly as scanned.
- Add touchpad libinput defaults: tap, natural scroll, middle emulation.
- Supported filesystems: `ext4` (and `vfat` via boot; add `ntfs-3g` only if required).
- Bootloader: systemd-boot with sane limits; reuse defaults (no CachyOS params; no NVIDIA kernel params).
- If discrete GPU absent, ensure `services.xserver.videoDrivers = [ "modesetting" ]` and remove PRIME/NVIDIA options.

## 5) Application Profile (lean)

- Enable:
  - WM stack: i3, i3status-rust, dunst, rofi, picom, greenclip, autorandr, xdg utilities.
  - Terminal/editor: kitty, neovim (nixvim), ripgrep, fd/fzf, jq, git, gnupg/ssh tools, zip/unzip/p7zip, coreutils, curl/wget, tealdeer, htop/bottom.
  - Browsers: floorp or firefox (choose one primary), optional chromium-free alt (librewolf) disabled by default.
  - File manager: nemo or pcmanfm; clipboard: xclip/xsel.
  - Notes/office: obsidian, logseq, planify/pandoc, zathura, nsxiv, mpv.
  - Networking: NetworkManager applet, openvpn if needed, tailscale optional (default off).
- Disable by default: steam/games, burpsuite/pentest suite, heavy SDKs (rust/go/java/clojure), virtualization (qemu/vmware/virtualbox), docker (enable only if required), cloudflare warp/cloudflared, R2 runtime, duplicati, git mirrors, system76 hardware apps, GPU tools, wine, upscayl, vscode-fhs unless requested.
- Update `apps-enable.nix` to reflect explicit enables/disables; keep `home-manager-apps` aligned to the same subset.

## 6) Services & UX

- Audio: pipewire + rtkit.
- Bluetooth: enable, power on boot.
- DBus/XDG portals: gtk portal for electron apps.
- Power: `power-profiles-daemon` on; no system76-power, no lact; logind lid/power actions = lock/suspend per office preference.
- Printing: default off; add CUPS only if required.
- Journald/coredump: tighten (e.g., journald `SystemMaxUse=200M`, coredump `MaxUse=512M`, `MaxRetentionSec=3d`).
- fstrim weekly on SSD.
- Firewall: on; allow 22/tcp only (adjust if services added).

## 7) Nix & Package Settings

- `nix.settings.experimental-features = [ "nix-command" "flakes" "pipe-operators" ]`.
- `auto-optimise-store = true`; `min-free = 8–10 GiB`; `max-jobs = 2–4`; `cores = 0` (auto).
- Substituters: reuse existing list or trim to `cache.nixos.org` + one fast mirror; keep trusted keys in sync.
- Optional `nix-ld` if VSCode server/FHS binaries are needed; otherwise omit to reduce closure size.

## 8) Secrets & Fonts

- Keep `sops-nix` key path `/var/lib/sops-nix/key.txt`; no extra age sshKeyPaths.
- R2/duplicati/mirrors: omit for tpnix unless explicitly requested.
- MonoLisa fonts: include only if secret `secrets/fonts/monolisa.tar.zst` exists; otherwise fall back to Noto + Nerd Fonts.

## 9) Deliverables (repo changes)

- `docs/tpnix/IMPLEMENTATION_PLAN.md` (this document).
- New host module set under `modules/tpnix/`:
  - `imports.nix`, `hardware-config.nix`, `hostname.nix`, `host-id.nix`, `network.nix`, `nix-settings.nix`, `state-version.nix`, `power.nix`, `apps-enable.nix`, `default-apps.nix`, optional `home-manager-apps.nix`, `fonts.nix`, `nix-ld.nix`.
- No changes to `modules/system76/*` other than shared multi-host support already updated.

## 10) Validation & Rollout

- Commands (from repo root):
  1. `nix flake check --accept-flake-config --no-build --offline`
  2. `nix build .#nixosConfigurations.tpnix.config.system.build.toplevel`
  3. Optional: `nix fmt` / `nix develop -c treefmt` if formatting changes arise.
- Deployment (when ready): `./build.sh --host tpnix --boot` (installs next-boot generation without activating). For dry build only, use `nix build .#nixosConfigurations.tpnix.config.system.build.toplevel`.
- Post-boot checks: networking (NM), audio (pw-cli/pavucontrol), display/i3 startx, suspend/resume, keyboard/touchpad, disk mounts, firewall ports.

## 11) Open Decisions

- Choose primary browser (floorp vs firefox) and file manager (nemo vs pcmanfm).
- Whether to keep docker enabled by default.
- Whether `nix-ld` is needed on this host.
- If any cloud sync (dropbox/maestral) is required by default.
- Printing support needed? (CUPS on/off).
- Tailscale/OpenVPN defaults.
