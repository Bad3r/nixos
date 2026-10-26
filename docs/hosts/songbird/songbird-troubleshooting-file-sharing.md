# Songbird troubleshooting: file sharing

- [songbird-troubleshooting.md](songbird-troubleshooting.md)

## The Samba media share is unreachable after boot

`modules/hosts/songbird/services.nix` detaches `samba.target` from `multi-user.target`, so smbd, nmbd, and wsdd stay down until the target is started by hand.

```sh
systemctl is-active samba.target
```

Start the target when it reports `inactive`.

```sh
sudo systemctl start samba.target
```

## The Samba media share is missing while samba.target runs

The share is skipped with a warning when `secrets/songbird.yaml` is absent or `sopsRuntimeReady` in `modules/hosts/songbird/policy.nix` is false.

Run the checks in the worktree that built the running generation, not the primary checkout at `$HOME/nixos`.
A `git+file:` evaluation of the primary checkout fetches the recorded `secrets` gitlink itself, so it cannot reveal an empty worktree submodule.
`path:` copies the worktree and submodule unfiltered into the world-readable Nix store, so the evaluation runs only when the secrets guard passes.

```sh
ls secrets/songbird.yaml
git status --porcelain --ignored=matching
git submodule foreach --recursive 'git status --porcelain --ignored=matching'
bash -c 'source scripts/lib/secrets-guard.sh && secrets_guard_enforce "$PWD" "path:$PWD"' &&
  nix eval "path:.#nixosConfigurations.songbird.config.warnings"
```

For an absent file, initialize the secrets submodule, since `secrets/songbird.yaml` is tracked there and `sops` against an empty checkout writes a stray file instead.

```sh
git submodule update --init --recursive
```

For a warning that names `sopsRuntimeReady`, set `sopsRuntimeReady = true` in `modules/hosts/songbird/policy.nix`.

## A switch fails with `the key 'samba_media_path' cannot be found`

`secrets/songbird.yaml` exists but has no `samba_media_path` key, which the media share's secret in `modules/hosts/songbird/services.nix` reads.

```sh
yq 'has("samba_media_path")' secrets/songbird.yaml
```

Add the key, then switch again.

```sh
sops secrets/songbird.yaml
```

## qBittorrent reports no incoming connections

The Proton tunnel has no handshake, so the NAT-PMP renewal inside the namespace fails and no mapped port reaches the session.

```sh
journalctl -u qbittorrent-port-forward.service -n 5
sudo ip netns exec torrent wg show wg-torrent
```

Restart the tunnel when the journal shows `NAT-PMP mapping failed` and `wg show` reports no recent handshake.

```sh
sudo systemctl restart wireguard-wg-torrent.service
```

A handshake that never returns means the Proton profile expired or the server retired, so rotate it per [the qBittorrent guide](../../guides/qbittorrent-web-ui-setup.md#songbird-rotate-the-proton-vpn-wireguard-profile).

## qBittorrent marks a torrent errored on its save path

The `qbittorrent` user cannot write the folder, because it lies outside every `saveRoots` tree in [qbittorrent.nix](../../../modules/hosts/songbird/qbittorrent.nix) or its ACL lacks a writable entry.

```sh
getfacl -p <folder>
```

Move a folder that sits outside the roots under one of them.
A folder moved in by `mv` carries no `user:qbittorrent` entry; apply the entries without waiting for the next switch or boot.

```sh
sudo systemd-tmpfiles --create --prefix=<root>
```

An entry marked `#effective:r-x` means a chmod cut the ACL mask; restore it.

```sh
setfacl -m m::rwx <folder>
```
