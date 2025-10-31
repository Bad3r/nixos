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
  config,
  lib,
  pkgs,
  ...
}:
let
  KdePackagesModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.kcolorchooser.extended;
    in
    {
      options.programs.kdePackages.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable kdePackages.";
        };

        package = lib.mkPackageOption pkgs "kdePackages" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.kdePackages = KdePackagesModule;
}
