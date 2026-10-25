# sbx bases

[`sbx`](README.md) cuts every sandbox from a base: a Nix-built image or a prepared cloud image.
Each sandbox gets a qcow2 overlay on its base and a fresh ed25519 key for root.

## Nix bases

A Nix base is the disk image at `legacyPackages.x86_64-linux.workloads.sbx-<base>` in `modules/apps/sbx/bases.nix`.
`nixos` comes from `modules/apps/sbx/_base-nixos.nix`, and `nixos-gui` adds `modules/apps/sbx/_base-nixos-gui.nix`.
`sbx base build <base>` builds it from the flake the `flake` option names, with an out-link under `~/.local/share/sbx/bases/` as its GC root.
No host closure references a base, and each sandbox adds its own GC root to the base it was cut from.
The key reaches the guest as the `ssh.authorized_keys.root` systemd credential over fw_cfg.

## GUI bases

- `nixos-gui` logs the user `sbx` into an X11 session with IceWM and a focused xterm.
- Commands from `exec` run as root with `DISPLAY` set to that session, so X clients such as `xdotool` show up there.
- `create nixos --gui` is `create nixos-gui`, and both default to the `guiMemory` option instead of `memory`.
- The domain carries a SPICE display on a unix socket, with clipboard and file transfer off and no vdagent channel.
  `virsh -c qemu:///session domdisplay sbx-<name>` prints its URI for a libvirt client.

| Verb                        | Effect                                   |
| --------------------------- | ---------------------------------------- |
| `screenshot <name> [--ocr]` | display to a file in `xfer`, opt. OCR    |
| `key <name> <chord>...`     | press each chord, such as `ctrl+alt+t`   |
| `type <name> <text>`        | type US-layout ASCII; newline is `enter` |

- A chord joins key names with `+`; an unknown name fails with the list of known ones.
- `key` and `type` refuse a sandbox on any other base with `no-display`.
- A key or character outside the layout fails with `invalid-argument` before anything reaches the guest.
- QEMU drops input past its queue, so `sbx` waits for each chord to land; a character takes about 20 ms, a shifted one about 40 ms.
- The guest's keyboard layout must be US for `type` to produce the characters it was given.

## Cloud bases

The `cloudImages` option in `modules/apps/sbx/nixos.nix` pins each cloud image by URL and SRI hash, always a dated build.
An image needs cloud-init with the NoCloud datasource, `systemd-ssh-generator`, and apt.

`sbx base prepare <image>` turns an image into a base, run by the owner from a shell outside any agent session:

1. It fetches the image with `nix store prefetch-file --expected-hash`, which fails on a hash mismatch.
   It refuses with `image-unsafe` when the qcow2 header names a backing file or an external data file.
2. It boots the image once as the sandbox `prepare-<image>` on the `egress` network.
3. Over SSH on vsock it installs `qemu-guest-agent`, resets cloud-init and the machine id, and skips `systemd-networkd-wait-online` on guests without a NIC.
4. It waits for the guest to power off and flattens the disk into `~/.local/share/sbx/bases/<image>/disk.qcow2`, read-only, replacing an older one.

```sh
sbx base prepare debian-13
sbx run debian-13 -- cat /etc/os-release
```

- `prepare` refuses with `owner-only` when `CLAUDE_CODE_SESSION_ID` or `CODEX_THREAD_ID` is set, and with `base-in-use` while a sandbox runs on the base.
- The `owner-only` refusal is a guard rail, not a boundary: an agent runs as the owner and can clear those variables, so the agents' permission rules also ask before `sbx base prepare`.
- A prepared base lives outside the Nix store, so no GC root protects it, and `base prepare` is the only path that replaces it.
- Each cloud sandbox boots with a NoCloud seed ISO that carries a fresh instance id, root's key, and no default user, so cloud-init runs again.
- A `none` sandbox's seed turns cloud-init networking off; an `egress` sandbox takes cloud-init's DHCP fallback on its NIC.
- The seed's `bootcmd` loads the vsock transport and starts `sshd-vsock.socket`, since Debian's cloud kernel loads that module after `systemd-ssh-generator` runs.

To pin a new build, check the download against the build's `SHA512SUMS`, then pin the SHA-256 of the checked file.
Debian publishes no signature for cloud builds, so the check rests on HTTPS to `cloud.debian.org`.

```sh
build=https://cloud.debian.org/images/cloud/trixie/<build>
image=debian-13-genericcloud-amd64-<build>.qcow2
sum=$(curl -fsSL "$build/SHA512SUMS" | awk -v f="$image" '$2 == f { print $1 }')
path=$(nix store prefetch-file --json --hash-type sha512 --expected-hash "$(nix hash to-sri --type sha512 "$sum")" "$build/$image" | jq -r .storePath)
nix hash file --type sha256 --sri "$path"
```
