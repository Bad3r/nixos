/*
  Package: networkmanager-openvpn
  Description: NetworkManager plugin providing OpenVPN integration.
  Homepage: https://wiki.gnome.org/Projects/NetworkManager
  Documentation: https://wiki.gnome.org/Projects/NetworkManager/VPN
  Repository: https://gitlab.gnome.org/GNOME/NetworkManager-openvpn

  Summary:
    * Extends NetworkManager with support for creating and managing OpenVPN connections.
    * Enables certificate, username/password, and static key authentication through GUI and CLI workflows.

  Options:
    --vpn-type openvpn: Specify the OpenVPN plugin when creating connections with `nmcli connection add`.
    --ask: Prompt interactively for secrets when activating a profile via `nmcli connection up --ask`.
    --show-secrets: Reveal stored credentials for troubleshooting with `nmcli connection show --show-secrets`.
*/

/*
  Package: networkmanager-openvpn
  Description: NetworkManager plugin providing OpenVPN integration.
  Homepage: https://wiki.gnome.org/Projects/NetworkManager
  Documentation: https://wiki.gnome.org/Projects/NetworkManager/VPN
  Repository: https://gitlab.gnome.org/GNOME/NetworkManager-openvpn

  Summary:
    * Extends NetworkManager with support for creating and managing OpenVPN connections.
    * Enables certificate, username/password, and static key authentication through GUI and CLI workflows.

  Options:
    nm-connection-editor: Create or edit OpenVPN profiles via the graphical editor.
    nmcli connection import type openvpn <file.ovpn>: Import OpenVPN configuration files.
    nmcli connection up <name>: Activate an OpenVPN connection from the command line.
*/

{
  flake.nixosModules.apps."networkmanager-openvpn" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.networkmanager-openvpn ];
    };
}
