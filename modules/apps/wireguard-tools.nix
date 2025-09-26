/*
  Package: wireguard-tools
  Description: Command-line utilities (`wg`, `wg-quick`) for managing WireGuard VPN tunnels.
  Homepage: https://www.wireguard.com/
  Documentation: https://www.wireguard.com/quickstart/
  Repository: https://git.zx2c4.com/wireguard-tools/

  Summary:
    * Configures WireGuard interfaces via simple configuration files, supporting key generation, peer management, and tunnel status reporting.
    * Includes `wg-quick` for bringing tunnels up/down using `/etc/wireguard/*.conf` files with DNS, routing, and firewall hooks.

  Options:
    wg genkey | wg pubkey: Generate private/public key pairs.
    wg show: Display interface and peer status.
    wg set <interface> <options>: Adjust peers and settings at runtime.
    wg-quick up <config>: Bring up a tunnel defined in `/etc/wireguard/<config>.conf`.
    wg-quick down <config>: Tear down a tunnel.

  Example Usage:
    * `wg genkey | tee privatekey | wg pubkey > publickey` — Generate keys for a peer.
    * `sudo wg-quick up wg0` — Start the `wg0` tunnel using `/etc/wireguard/wg0.conf`.
    * `sudo wg show wg0` — Inspect handshake times, transfer statistics, and peer endpoints.
*/

{
  flake.nixosModules.apps."wireguard-tools" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.wireguard-tools ];
    };

}
