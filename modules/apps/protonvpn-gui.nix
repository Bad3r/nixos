/*
  Package: protonvpn-gui
  Description: Official ProtonVPN desktop application with secure core, NetShield, and auto-connect features.
  Homepage: https://protonvpn.com/
  Documentation: https://protonvpn.com/support/linux-vpn-tool/
  Repository: https://github.com/ProtonVPN/linux-app

  Summary:
    * Provides a GTK interface for ProtonVPN, supporting OpenVPN and WireGuard connections, profiles, kill switch, split tunneling, and notifications.
    * Integrates Proton account login, multi-hop (Secure Core), NetShield malware/ad blocking, and connection speed metrics.

  Options:
    protonvpn-gui: Launch the ProtonVPN desktop client and sign in with Proton credentials.
    CLI: ProtonVPN GUI also installs `protonvpn-cli` for headless control (`protonvpn-cli c`, `protonvpn-cli status`, etc.).

  Example Usage:
    * `protonvpn-gui` — Open the GUI, select a profile, and connect to a VPN server.
    * `protonvpn-cli c --sc` — Connect to the fastest Secure Core server via CLI.
    * Enable “Kill Switch” in settings to block traffic if the VPN disconnects unexpectedly.
*/
_:
let
  ProtonvpnGuiModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."protonvpn-gui".extended;
    in
    {
      options.programs.protonvpn-gui.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable protonvpn-gui.";
        };

        package = lib.mkPackageOption pkgs "protonvpn-gui" { };
      };

      config = lib.mkIf cfg.enable {
        nixpkgs.config.allowedUnfreePackages = [ "protonvpn-gui" ];

        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.protonvpn-gui = ProtonvpnGuiModule;
}
