# Songbird torrent runbook

Procedures for the qBittorrent service that [qbittorrent.nix](../../modules/songbird/qbittorrent.nix) runs inside the `torrent` network namespace behind a Proton VPN WireGuard tunnel.
The Web UI opens with `qbittorrent-webui`, which is also the handler behind magnet links and `.torrent` files.

## Move the desktop client's torrents into the service

Precondition: the switch that enables the service has run, and the Qt client has been closed once since its last change, so its resume data is complete.

1. Stop the service:

   ```sh
   sudo systemctl stop qbittorrent.service
   ```

2. Copy the resume data and the categories into the service profile, which the service user owns:

   ```sh
   install -d /var/lib/qBittorrent/qBittorrent/data/BT_backup
   cp ~/.local/share/qBittorrent/BT_backup/* /var/lib/qBittorrent/qBittorrent/data/BT_backup/
   cp ~/.config/qBittorrent/categories.json /var/lib/qBittorrent/qBittorrent/config/
   ```

3. Start the service and open the Web UI:

   ```sh
   sudo systemctl start qbittorrent.service
   qbittorrent-webui
   ```

Verification: the Web UI lists every torrent the Qt client held at the same save paths, and `journalctl -u qbittorrent-port-forward.service` ends with a `listen port set to` line.

## Rotate the Proton VPN WireGuard profile

Precondition: a new WireGuard configuration from the Proton account page, generated for a P2P server with NAT-PMP port forwarding on.

1. Put its `PrivateKey` under `songbird.wireguard_private_key`:

   ```sh
   sops secrets/protonvpn.yaml
   ```

2. Set the peer's `PublicKey` and `Endpoint` in [qbittorrent.nix](../../modules/songbird/qbittorrent.nix), then commit the secrets repository, the gitlink, and the module, and switch.

3. Replace the endpoint entry on the `nixos-songbird` WARP profile per [change a profile's exclude list](../cloudflare/warp/deployment.md#change-a-profiles-exclude-list).

Verification: `sudo ip netns exec torrent wg show wg-torrent` reports a recent handshake, and `sudo ip netns exec torrent natpmpc -g 10.2.0.1` prints the new server's public address.

## Reach the Web UI from another host

Precondition: the host is reachable over SSH, since the Web UI listens on the loopback only and skips authentication there.

1. Forward the port over SSH:

   ```sh
   ssh -N -L 8080:127.0.0.1:8080 songbird.warp
   ```

2. Open `http://127.0.0.1:8080` in the browser on the other host.

Verification: the Web UI loads without a login prompt.
