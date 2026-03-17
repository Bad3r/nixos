/*
  Package: snip
  Description: Terminal snippet manager for storing, searching, and reusing code snippets.
  Homepage: https://github.com/phlx0/snip
  Documentation: https://github.com/phlx0/snip/wiki/CLI-Reference
  Repository: https://github.com/phlx0/snip

  Summary:
    * Opens a local Textual TUI for browsing, editing, and tagging saved snippets offline.
    * Supports direct CLI lookup, JSON export/import, and running saved snippets as shell commands.

  Options:
    run: Execute a matching snippet as a shell command.
    --list [tag]: Print snippet titles, optionally filtered by tag.
    --add <file>: Save a file as a snippet with language detection from its extension.
    --db <path>: Use a custom SQLite database instead of the default config path.
    theme: List, set, or import UI themes from the CLI.
*/
_:
let
  SnipModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.snip.extended;
    in
    {
      options.programs.snip.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable snip.";
        };

        package = lib.mkPackageOption pkgs "snip" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.snip = SnipModule;
}
