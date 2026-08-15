/*
  Package: autotrace
  Description: Utility for converting bitmap images into vector graphics.
  Homepage: nil
  Documentation: https://github.com/autotrace/autotrace#readme
  Repository: https://github.com/autotrace/autotrace

  Summary:
    * Converts bitmap images into SVG, EPS, PDF, DXF, and other vector formats.
    * Supports outline and centerline tracing, color reduction, and despeckling.

  Options:
    <input> -output-file <output>: Convert a bitmap image to a vector file.
    -centerline: Trace centerlines instead of outlines.
    -color-count <count>: Reduce the number of colors before tracing.
    --list-input-formats: List supported input formats.
    --list-output-formats: List supported output formats.
*/
_:
let
  AutotraceModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.autotrace.extended;
    in
    {
      options.programs.autotrace.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable autotrace.";
        };

        package = lib.mkPackageOption pkgs "autotrace" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.autotrace = AutotraceModule;
}
