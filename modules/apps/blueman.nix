/*
  Package: blueman
  Description: GTK-based Bluetooth Manager.
  Homepage: https://github.com/blueman-project/blueman
  Documentation: https://github.com/blueman-project/blueman/wiki
  Repository: https://github.com/blueman-project/blueman

  Summary:
    * Provides a GTK front end for pairing devices, managing adapters, and handling Bluetooth service actions on top of BlueZ.
    * Ships desktop entrypoints for the main device manager, session applet, file sending, and service configuration.

  Options:
    blueman-manager: Launch the primary Bluetooth management window for pairing and device administration.
    blueman-applet: Start the session applet that exposes quick adapter and connection actions.
    blueman-sendto: Send files to paired devices over OBEX.
    blueman-services: Configure Bluetooth service plugins for connected devices.

  Notes:
    * The nixpkgs package is `blueman`; the main GUI launcher users typically run is `blueman-manager`.
*/
_:
let
  BluemanModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.blueman.extended;
    in
    {
      options.programs.blueman.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable blueman.";
        };

        package = lib.mkPackageOption pkgs "blueman" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
        services.blueman.enable = true;
      };
    };
in
{
  flake.nixosModules.apps.blueman = BluemanModule;
}
