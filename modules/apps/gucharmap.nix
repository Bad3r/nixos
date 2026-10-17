/*
  Package: gucharmap
  Description: GNOME Character Map, a Unicode character map based on the Unicode Character Database.
  Homepage: https://gitlab.gnome.org/GNOME/gucharmap
  Documentation: https://gitlab.gnome.org/GNOME/gucharmap/-/blob/master/help/C/index.docbook
  Repository: https://gitlab.gnome.org/GNOME/gucharmap

  Summary:
    * Browses the Unicode character set by script or by Unicode block and shows each character's code point, name, and details.
    * Searches character names and details, and collects characters in a text field for copying into other applications.

  Options:
    --font=FONT: Start with the given font, for example 'Serif 27'.
    -p, --print=STRING: Print each character of STRING with its code point and Unicode name, then exit.
*/
_:
let
  GucharmapModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.gucharmap.extended;
    in
    {
      options.programs.gucharmap.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable gucharmap.";
        };

        package = lib.mkPackageOption pkgs "gucharmap" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.gucharmap = GucharmapModule;
}
