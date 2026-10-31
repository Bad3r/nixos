/*
  Package: networkmanager-dmenu
  Description: dmenu/rofi front-end for NetworkManager to switch wireless and VPN connections via keyboard shortcuts.
  Homepage: https://github.com/firecat53/networkmanager-dmenu
  Documentation: https://github.com/firecat53/networkmanager-dmenu#readme
  Repository: https://github.com/firecat53/networkmanager-dmenu

  Summary:
    * Provides shell scripts that enumerate NetworkManager connections and present them through dmenu, rofi, or wofi interfaces.
    * Enables quick connection toggling and VPN activation without opening graphical applets.
*/
_:
let
  NetworkmanagerDmenuModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."networkmanager-dmenu".extended;
    in
    {
      options.programs."networkmanager-dmenu".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable networkmanager-dmenu.";
        };

        package = lib.mkPackageOption pkgs "networkmanager_dmenu" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."networkmanager-dmenu" = NetworkmanagerDmenuModule;
}
