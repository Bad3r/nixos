/*
  Package: networkmanager-dmenu
  Description: dmenu/rofi front-end for NetworkManager to switch wireless and VPN connections via keyboard shortcuts.
  Homepage: https://github.com/firecat53/networkmanager-dmenu
  Documentation: https://github.com/firecat53/networkmanager-dmenu#readme
  Repository: https://github.com/firecat53/networkmanager-dmenu

  Summary:
    * Provides shell scripts that enumerate NetworkManager connections and present them through dmenu, rofi, or wofi interfaces.
    * Enables quick connection toggling, VPN activation, and QR code display without opening graphical applets.

  Options:
    networkmanager_dmenu: Launch the standard dmenu interface.
    networkmanager_dmenu -l rofi: Use rofi instead of dmenu (requires rofi installed).
    networkmanager_dmenu --qr: Show QR codes for sharing Wi-Fi credentials.
    Config files in `~/.config/networkmanager-dmenu/`: Customize prompts, fonts, and commands.

  Example Usage:
    * `networkmanager_dmenu` — Select a Wi-Fi network using dmenu.
    * `networkmanager_dmenu -l rofi --visible` — Launch with rofi and keep the menu open after selection.
    * `networkmanager_dmenu --qr` — Display the QR code for the currently active Wi-Fi connection.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs."networkmanager-dmenu".extended;
  NetworkmanagerDmenuModule = {
    options.programs."networkmanager-dmenu".extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = lib.mdDoc "Whether to enable networkmanager-dmenu.";
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
