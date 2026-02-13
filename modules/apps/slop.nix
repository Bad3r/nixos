/*
  Package: slop
  Description: Interactive selector that captures screen regions and outputs geometry.
  Homepage: https://github.com/naelstrof/slop
  Documentation: https://github.com/naelstrof/slop#readme
  Repository: https://github.com/naelstrof/slop

  Summary:
    * Queries the user for a rectangular region or window selection and prints coordinates for scripts.
    * Supports configurable border, color, and formatting controls for screenshot and recording workflows.

  Options:
    -b, --bordersize=FLOAT: Set selection border thickness.
    -c, --color=FLOAT,FLOAT,FLOAT,FLOAT: Set selection color in RGBA floats.
    -f, --format=STRING: Set output format tokens such as %x, %y, %w, %h, and %g.
    -n, --nodecorations=INT: Attempt to select child windows to avoid window decorations.
    -t, --tolerance=FLOAT: Set movement threshold between click and drag behavior.
*/
_:
let
  SlopModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.slop.extended;
    in
    {
      options.programs.slop.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable slop.";
        };

        package = lib.mkPackageOption pkgs "slop" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.slop = SlopModule;
}
