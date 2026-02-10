/*
  Package: just
  Description: Command runner and make alternative.
  Homepage: https://just.systems/
  Documentation: https://just.systems/man/en/
  Repository: https://github.com/casey/just

  Summary:
    * Runs commands from a `justfile` with readable recipe syntax, dependency ordering, and argument passing.
    * Supports variables, default recipes, dotenv loading, and shell customization for repeatable project automation.

  Options:
    --justfile <FILE>: Use a specific justfile instead of searching in the working directory hierarchy.
    --working-directory <DIR>: Change directory before loading recipes and executing commands.
    --list: Print available recipes with their doc comments and exit.
    --choose: Open an interactive selector to pick and run a recipe.
    --set <VARIABLE> <VALUE>: Override a justfile variable for the current invocation.
*/
_:
let
  JustModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.just.extended;
    in
    {
      options.programs.just.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable just.";
        };

        package = lib.mkPackageOption pkgs "just" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.just = JustModule;
}
