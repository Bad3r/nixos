/*
  Package: ktailctl
  Description: KDE Plasma applet and utility for managing USB-C/Thunderbolt docks and external displays.
  Homepage: https://github.com/f-koehler/KTailctl
  Documentation: https://github.com/f-koehler/KTailctl#readme
  Repository: https://github.com/f-koehler/KTailctl

  Summary:
    * Provides a GUI for configuring display arrangements, audio routing, and power delivery on hardware requiring DisplayLink or USB-C hubs.
    * Includes command-line helpers for querying and applying saved docking profiles.

  Options:
    ktailctl: Launch the graphical control center for managing dock settings.
    ktailctl --list: List available display configurations and detected docks.
    ktailctl --apply <profile>: Apply a saved docking profile programmatically.

  Example Usage:
    * `ktailctl` — Open the KDE interface to manage USB-C dock displays and audio routing.
    * `ktailctl --list` — Inspect detected docks and saved profiles from the terminal.
    * `ktailctl --apply office` — Switch to a predefined “office” docking layout.
*/

{
  flake.nixosModules.apps.ktailctl =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.ktailctl ];
    };

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.ktailctl ];
    };
}
