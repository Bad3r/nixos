/*
  Package: kcolorchooser
  Description: Qt-based color picker with palette management and screen sampling.
  Homepage: https://apps.kde.org/kcolorchooser/
  Documentation: https://apps.kde.org/kcolorchooser/
  Repository: https://invent.kde.org/graphics/kcolorchooser

  Summary:
    * Picks colors anywhere on the screen with an eyedropper tool.
    * Displays color values in multiple formats (HTML hex, RGB, HSV) and edits palette entries.
    * Prints the selected color to stdout with `--print`.
*/
_:
let
  KcolorchooserModule =
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
      options.programs.kcolorchooser.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable KColorChooser color picker.";
        };

        package = lib.mkPackageOption pkgs [ "kdePackages" "kcolorchooser" ] { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.kcolorchooser = KcolorchooserModule;
}
