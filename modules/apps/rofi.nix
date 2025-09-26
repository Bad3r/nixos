/*
  Package: rofi
  Description: Window switcher, application launcher, and dmenu replacement with plugin system.
  Homepage: https://github.com/davatorium/rofi
  Documentation: https://github.com/davatorium/rofi/blob/next/doc/rofi.1.md
  Repository: https://github.com/davatorium/rofi

  Summary:
    * Provides a customizable launcher supporting modes for running applications, switching windows, SSH, scripts, file browsers, and more.
    * Features themes, keybinding customization, history, and scriptable “modi” to extend functionality beyond launching apps.

  Options:
    rofi -show drun: Launch desktop applications using .desktop entries.
    rofi -show run: Launch commands similar to dmenu.
    rofi -modi window,drun,ssh -show window: Enable multiple modes with keybindings.
    rofi -theme <theme.rasi>: Apply a custom theme.
    rofi -dmenu: Emulate dmenu for use with existing scripts.

  Example Usage:
    * `rofi -show drun` — Display the application launcher.
    * `rofi -show ssh` — Quickly SSH into hosts listed in `~/.ssh/config`.
    * `echo -e "Option1\nOption2" | rofi -dmenu -p "Choose:"` — Use rofi as an interactive selection menu in scripts.
*/

{
  flake.nixosModules.apps.rofi =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.rofi ];
    };

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.rofi ];
    };
}
