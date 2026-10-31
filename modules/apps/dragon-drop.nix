/*
  Package: dragon-drop
  Description: Lightweight drag-and-drop bridge that makes files from the terminal or clipboard available to graphical apps.
  Homepage: https://github.com/mwh/dragon
  Documentation: https://github.com/mwh/dragon#readme
  Repository: https://github.com/mwh/dragon

  Summary:
    * Shows draggable icons for files given as arguments or on stdin.
    * Can act as a drop target that prints dropped URIs, or paths with `-p`.

  Options:
    dragon-drop -t: Act as a drop target instead of a source.
    dragon-drop -I: Read file paths from stdin.
    dragon-drop -a: Drag all files at once.
    dragon-drop -x: Exit after a single completed drop.

  Notes:
    * `xdragon` is an alias for `dragon-drop`.
*/
_:
let
  DragonDropModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."dragon-drop".extended;
    in
    {
      options.programs.dragon-drop.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable dragon-drop.";
        };

        package = lib.mkPackageOption pkgs "dragon-drop" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.dragon-drop = DragonDropModule;
}
