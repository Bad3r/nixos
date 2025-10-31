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
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.networkmanager-openvpn.extended;
  NetworkmanagerOpenvpnModule = {
    options.programs.networkmanager-openvpn.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true; # Backward compatibility - TODO: flip to false in Phase 2
        description = lib.mdDoc "Whether to enable networkmanager-openvpn.";
      };

      package = lib.mkPackageOption pkgs "networkmanager-openvpn" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.networkmanager-openvpn = NetworkmanagerOpenvpnModule;
}
