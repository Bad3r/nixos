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
  flake.nixosModules.apps."networkmanager-dmenu" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.networkmanager_dmenu ];
    };

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.networkmanager_dmenu ];
    };
}
