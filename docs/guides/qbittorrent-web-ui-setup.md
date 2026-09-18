# qBittorrent Web UI setup

Use qBittorrent through a host's Web UI instead of its desktop client.
Songbird is the example host: [qbittorrent.nix](../../modules/songbird/qbittorrent.nix) runs the service inside the `torrent` network namespace behind Proton VPN.
The `qbittorrent-webui` handler opens each magnet link or `.torrent` file in the add dialog of Songbird's Web UI, which sets the category and save path before the torrent is added.

## Optional: import torrents from the desktop profile

Precondition: the desktop profile's `BT_backup` directory is readable, and the service can access every old save path.
On Songbird, each path must sit under `saveRoots` in [qbittorrent.nix](../../modules/songbird/qbittorrent.nix).
Songbird reads resume data from `torrents.db`, so copying `BT_backup` into its service profile imports nothing.

Set `webui` to the qBittorrent Web API base URL.
The Songbird example needs no login:

```sh
webui=http://$(systemctl show -P Listen qbittorrent-webui.socket | cut -d' ' -f1)
```

1. In the `BT_backup` directory, list each torrent's hash, save path, category, and skipped file indexes:

   ```sh
   uv run --python 3.14 --with bencode.py python - <<'EOF'
   import bencodepy, pathlib
   for t in sorted(pathlib.Path().glob("*.torrent")):
       d = bencodepy.decode(t.with_suffix(".fastresume").read_bytes())
       skipped = [str(i) for i, p in enumerate(d.get(b"file_priority", [])) if p == 0]
       print(t.stem, (d[b"qBt-savePath"] or d[b"save_path"]).decode(), d[b"qBt-category"].decode(), "|".join(skipped))
   EOF
   ```

   A `.fastresume` with no `.torrent` beside it is a magnet link that never fetched metadata; add it again by its magnet link.

2. Add each torrent stopped at its listed save path, under an existing service category in its exact letter case, since any other name creates a new category:

   ```sh
   curl -fsS -F torrents=@<hash>.torrent -F "savepath=<path>" -F "category=<category>" -F stopped=true -F autoTMM=false -F contentLayout=Original "$webui/api/v2/torrents/add"
   ```

   `autoTMM=false` keeps that path, since the service manages new torrents automatically and would place each one at its category's path.

3. Deselect each torrent's listed skipped files, which the add call rejects alongside an uploaded `.torrent`:

   ```sh
   curl -fsS --data-urlencode hash=<hash> --data-urlencode 'id=<indexes>' -d priority=0 "$webui/api/v2/torrents/filePrio"
   ```

4. Recheck the added torrents, which starts each one for its check and stops it again when the check ends:

   ```sh
   curl -fsS --data-urlencode 'hashes=<hash>|<hash>' "$webui/api/v2/torrents/recheck"
   ```

Verification: `curl -fsS "$webui/api/v2/torrents/info?filter=stopped" | jq -r '.[] | "\(.progress) \(.save_path) \(.name)"'` lists each added torrent at its save path with the progress the other profile recorded.

## Songbird: save torrents under a save root

Precondition: the folder is under a tree in `saveRoots` in [qbittorrent.nix](../../modules/songbird/qbittorrent.nix); `~/Downloads` is the only part of the home directory the service can see.

1. Create the folder with any tool, or type its path into a save path field and let the Web UI create it.
2. Set it as the save path of a category or of a single torrent.
   The default save path is `DefaultSavePath` in [qbittorrent.nix](../../modules/songbird/qbittorrent.nix); a change under Options lasts only until the next restart.

Verification: `getfacl -p <folder>` lists a `user:qbittorrent:rwx` and a `default:user:qbittorrent:rwx` entry, and a torrent saved there completes without an errored state.

## Songbird: rotate the Proton VPN WireGuard profile

Precondition: a new WireGuard configuration from the [Proton account page](https://account.protonvpn.com/downloads), generated for a P2P server with NAT-PMP port forwarding on.

1. Put its `PrivateKey` under `songbird.wireguard_private_key`:

   ```sh
   sops secrets/protonvpn.yaml
   ```

2. Set the peer's `PublicKey` and `Endpoint` in [qbittorrent.nix](../../modules/songbird/qbittorrent.nix), then commit the secrets repository, the gitlink, and the module, and switch.

Verification: `sudo ip netns exec torrent wg show wg-torrent` reports a recent handshake, and `sudo ip netns exec torrent natpmpc -g 10.2.0.1` prints the new server's public address.
