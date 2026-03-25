/*
  Package: proton-vpn
  Description: Official ProtonVPN desktop application with secure core, NetShield, and auto-connect features.
  Homepage: https://protonvpn.com/
  Documentation: https://protonvpn.com/support/linux-vpn-tool/
  Repository: https://github.com/ProtonVPN/linux-app

  Summary:
    * Provides a GTK interface for ProtonVPN, supporting OpenVPN and WireGuard connections, profiles, kill switch, split tunneling, and notifications.
    * Integrates Proton account login, multi-hop (Secure Core), NetShield malware/ad blocking, and connection speed metrics.

  Options:
    protonvpn-app: Launch the ProtonVPN desktop client and sign in with Proton credentials.
    CLI: This package installs `protonvpn-app` as its main program.

  Example Usage:
    * `protonvpn-app` -- Open the GUI, select a profile, and connect to a VPN server.
    * `protonvpn-app --start-minimized` -- Launch the app with tray-first behavior.
    * Enable “Kill Switch” in settings to block traffic if the VPN disconnects unexpectedly.
*/
_:
let
  ProtonVpnModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."proton-vpn".extended;
    in
    {
      options.programs."proton-vpn".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable proton-vpn.";
        };

        package = lib.mkPackageOption pkgs "proton-vpn" { };
      };

      config = lib.mkIf cfg.enable {

        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [ "proton-vpn" ];
  flake.nixosModules.apps."proton-vpn" = ProtonVpnModule;
}
