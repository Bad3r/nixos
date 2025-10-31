/*
  Package: localsend
  Description: Cross-platform, open-source AirDrop alternative for offline file transfers.
  Homepage: https://localsend.org/
  Documentation: https://localsend.org/docs/
  Repository: https://github.com/localsend/localsend

  Summary:
    * Discovers nearby devices on the local network via mDNS and transfers files securely with TLS without requiring internet connectivity.
    * Provides a Flutter-based GUI supporting multiple concurrent transfers, text snippets, and links between desktop and mobile platforms.

  Options:
    localsend: Launch the graphical interface.
    Settings menu: Configure transfer directories, network interfaces, and optional relays.
    (CLI options are minimal; functionality is primarily through the GUI.)

  Example Usage:
    * `localsend` — Start the app and accept incoming transfers from mobile devices running LocalSend.
    * Use the GUI “Send” button to drop files onto another detected device.
    * Adjust settings to auto-accept files into a specific downloads directory.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  LocalsendModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.localsend.extended;
    in
    {
      options.programs.localsend.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable localsend.";
        };

        package = lib.mkPackageOption pkgs "localsend" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.localsend = LocalsendModule;
}
