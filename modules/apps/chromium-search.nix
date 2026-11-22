/*
  Package: chromium-search
  Description: Command-line interface for Chromium Code Search on source.chromium.org.
  Homepage: https://github.com/jclay/chromium-search
  Documentation: https://github.com/jclay/chromium-search#readme
  Repository: https://github.com/jclay/chromium-search

  Summary:
    * Searches Chromium source with the Code Search query syntax and prints matches, JSON, or links.
    * Finds files by name and prints files at a branch, tag, or commit.

  Options:
    chromium-search <query>: Search source code; supports lang:, file:, class:, function:, symbol:, usage:, and pcre:.
    find <name>: List file paths that match a name.
    cat <path> [--ref <ref>] [-n]: Print a file at a git ref, optionally with line numbers.
    syntax: Print the query syntax reference.
    CR_SEARCH_API_KEY: Replace the public Code Search API key the script ships with.

  Notes:
    * Sends requests only to grimoireoss-pa.clients6.google.com, the API behind source.chromium.org, and no telemetry.
    * Depends on an undocumented Google API, which can change without notice.
*/
_:
let
  ChromiumSearchModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."chromium-search".extended;
    in
    {
      options.programs.chromium-search.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable chromium-search.";
        };

        package = lib.mkPackageOption pkgs "chromium-search" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.chromium-search = ChromiumSearchModule;
}
