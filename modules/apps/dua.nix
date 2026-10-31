/*
  Package: dua
  Description: Interactive disk usage analyzer written in Rust.
  Homepage: https://github.com/Byron/dua-cli
  Documentation: https://github.com/Byron/dua-cli#readme
  Repository: https://github.com/Byron/dua-cli

  Summary:
    * Traverses directories quickly and shows usage in an interactive TUI for cleanup.
    * Prints non-interactive summaries for scripts.

  Options:
    dua aggregate <paths>: Print the space used by one or more paths.
    dua i <path>: Open the inspector focused on a specific directory tree.
*/
_:
let
  DuaModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.dua.extended;
    in
    {
      options.programs.dua.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable dua.";
        };

        package = lib.mkPackageOption pkgs "dua" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.dua = DuaModule;
}
