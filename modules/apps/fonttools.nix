/*
  Package: fonttools
  Description: Library and tools to manipulate font files from Python.
  Homepage: https://github.com/fonttools/fonttools
  Documentation: https://fonttools.readthedocs.io/
  Repository: https://github.com/fonttools/fonttools

  Summary:
    * Provides CLI and Python APIs for inspecting, subsetting, and converting OpenType/TrueType fonts.
    * Includes utilities like `pyftsubset`, `ttx`, and `fonttools varLib` for font engineering workflows.

  Options:
    ttx <font-file>: Convert between binary font formats and editable XML.
    pyftsubset <font-file> --text="...": Generate minimized subset fonts for specific glyph sets.
    fonttools varLib <designspace-file>: Build variable fonts from a designspace file.
*/
_:
let
  FonttoolsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.fonttools.extended;
    in
    {
      options.programs.fonttools.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable fonttools.";
        };

        package = lib.mkPackageOption pkgs [ "python3Packages" "fonttools" ] { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.fonttools = FonttoolsModule;
}
