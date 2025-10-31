/*
  Package: dua
  Description: Interactive disk usage analyzer written in Rust.
  Homepage: https://github.com/Byron/dua-cli
  Documentation: https://github.com/Byron/dua-cli#readme
  Repository: https://github.com/Byron/dua-cli

  Summary:
    * Traverses directories quickly and presents usage statistics with an interactive TUI for cleanup.
    * Offers non-interactive summaries suitable for scripting and CI reports.

  Options:
    dua: Launch the interactive terminal interface in the current directory.
    dua --summarize <paths>: Emit aggregate usage information for one or more paths.
    dua i <path>: Open the inspector focused on a specific directory tree.

  Example Usage:
    * `dua` — Inspect disk usage interactively starting at the current working directory.
    * `dua --summarize ~/Downloads ~/Videos` — Compare storage consumption across multiple directories.
    * `dua i /var/log` — Drill into nested directories and delete files directly from the TUI.
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
          description = lib.mdDoc "Whether to enable dua.";
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
