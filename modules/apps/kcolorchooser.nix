/*
  Package: kcolorchooser
  Description: Qt-based color picker with palette management and screen sampling.
  Homepage: https://apps.kde.org/kcolorchooser/
  Documentation: https://apps.kde.org/kcolorchooser/
  Repository: https://invent.kde.org/graphics/kcolorchooser

  Summary:
    * Provides a simple KDE Gear interface to pick colors anywhere on the screen via an eyedropper tool.
    * Displays color values in multiple formats (HTML hex, RGB, HSV) and supports editing palette entries.
    * Can print the selected color to stdout with `--print`, making script integration straightforward.

  Example Usage:
    * `kcolorchooser` — Launch the GUI picker with the default palette.
    * `kcolorchooser --print` — Copy a sampled color to stdout as soon as it is confirmed.
    * `kcolorchooser --color "#AABBCC"` — Preload the dialog with a specific color for adjustments.
*/

{
  flake.nixosModules.apps.kcolorchooser =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.kdePackages.kcolorchooser ];
    };
}
