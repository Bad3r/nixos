/*
  Package: cutter
  Description: Free and open-source reverse engineering platform powered by Rizin, with modern Qt GUI.
  Homepage: https://cutter.re/
  Documentation: https://cutter.re/docs/
  Repository: https://github.com/rizinorg/cutter

  Summary:
    * Graph, hex editor, and decompiler views for binary analysis.
    * Supports Python and C++ plugins.

  Options:
    cutter --help: Show all command-line options.
*/
_:
let
  CutterModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.cutter.extended;
    in
    {
      options.programs.cutter.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable Cutter (Rizin GUI frontend).";
        };

        package = lib.mkPackageOption pkgs "cutter" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.cutter = CutterModule;
}
