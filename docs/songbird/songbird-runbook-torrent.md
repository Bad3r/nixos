# Songbird torrent runbook

Procedures for the qBittorrent service that [qbittorrent.nix](../../modules/songbird/qbittorrent.nix) runs as the `qbittorrent` system user inside the `torrent` network namespace behind a Proton VPN WireGuard tunnel.
The Web UI opens with `qbittorrent-webui`, which is also the handler behind magnet links and `.torrent` files.

## Move the desktop client's torrents into the service

Precondition: the switch that enables the service has run, and the Qt client has been closed once since its last change, so its resume data is complete.

1. Stop the service:

   ```sh
   sudo systemctl stop qbittorrent.service
   ```

2. Copy the resume data and the categories into the service profile, owned by the `qbittorrent` user:

   ```sh
   sudo install -d -m 0700 -o qbittorrent -g qbittorrent /var/lib/qBittorrent/qBittorrent/data /var/lib/qBittorrent/qBittorrent/data/BT_backup
   sudo install -m 0600 -o qbittorrent -g qbittorrent ~/.local/share/qBittorrent/BT_backup/* /var/lib/qBittorrent/qBittorrent/data/BT_backup/
   sudo install -m 0600 -o qbittorrent -g qbittorrent ~/.config/qBittorrent/categories.json /var/lib/qBittorrent/qBittorrent/config/
   ```

3. Start the service and open the Web UI:

   ```sh
   sudo systemctl start qbittorrent.service
   qbittorrent-webui
   ```

Verification: the Web UI lists every torrent the Qt client held at the same save paths, and `journalctl -u qbittorrent-port-forward.service` ends with a `listen port set to` line.

## Save torrents into a folder under a save root

Precondition: the folder is under a tree in `saveRoots` in [qbittorrent.nix](../../modules/songbird/qbittorrent.nix); `~/Downloads` is the only part of the home directory the service can see.

1. Create the folder with any tool, or type its path into a save path field and let the Web UI create it.
2. Set it as the save path of a category or of a single torrent.
   The default save path is `DefaultSavePath` in [qbittorrent.nix](../../modules/songbird/qbittorrent.nix); a change under Options lasts only until the next restart.

Verification: `getfacl -p <folder>` lists a `user:qbittorrent:rwx` and a `default:user:qbittorrent:rwx` entry, and a torrent saved there completes without an errored state.

## Rotate the Proton VPN WireGuard profile

Precondition: a new WireGuard configuration from the Proton account page, generated for a P2P server with NAT-PMP port forwarding on.

1. Put its `PrivateKey` under `songbird.wireguard_private_key`:

   ```sh
   sops secrets/protonvpn.yaml
   ```

2. Set the peer's `PublicKey` and `Endpoint` in [qbittorrent.nix](../../modules/songbird/qbittorrent.nix), then commit the secrets repository, the gitlink, and the module, and switch.

Verification: `sudo ip netns exec torrent wg show wg-torrent` reports a recent handshake, and `sudo ip netns exec torrent natpmpc -g 10.2.0.1` prints the new server's public address.

## Reach the Web UI from another host

Precondition: the other host is on the local network or enrolled in Cloudflare Mesh.

1. Open `http://songbird.internal:8989` in the browser on a fleet host, or songbird's LAN or Mesh address on that port from any other device.
   Fleet browsers run HTTPS-Only Mode, which asks before it loads the HTTP page.

Verification: the Web UI loads without a login prompt.
