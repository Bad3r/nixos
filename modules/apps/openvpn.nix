/*
  Package: openvpn
  Description: Open-source VPN client and server implementing SSL/TLS-based virtual private networks.
  Homepage: https://openvpn.net/
  Documentation: https://openvpn.net/community-resources/reference-manual-for-openvpn-2-5/
  Repository: https://github.com/OpenVPN/openvpn

  Summary:
    * Creates secure tunnels over TCP/UDP using TLS certificates, static keys, or username/password authentication.
    * Supports site-to-site and client-to-site topologies, compression, split tunneling, and extensive scripting hooks.

  Options:
    openvpn --config <file>: Start a VPN using an .ovpn configuration file.
    --daemon: Run as a background daemon.
    --auth-user-pass [file]: Provide credentials interactively or from a file.
    --management <ip> <port>: Enable management interface for remote control.
    --log <file>: Write logs to a specific file for diagnostics.

  Example Usage:
    * `sudo openvpn --config client.ovpn` — Connect to a VPN using the provided configuration.
    * `sudo openvpn --config site.conf --daemon --log /var/log/openvpn.log` — Run OpenVPN in the background with logging.
    * `sudo openvpn --config client.ovpn --auth-user-pass creds.txt` — Supply username/password from a file for authentication.
*/

{
  flake.nixosModules.apps.openvpn =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.openvpn ];
    };

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.openvpn ];
    };
}
