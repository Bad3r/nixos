/*
  Package: ripgrep
  Description: Line-oriented search tool that recursively searches directories for regex patterns.
  Homepage: https://github.com/BurntSushi/ripgrep
  Documentation: https://github.com/BurntSushi/ripgrep/blob/master/GUIDE.md
  Repository: https://github.com/BurntSushi/ripgrep

  Summary:
    * High-performance recursive search tool with regex support, smart case matching, and automatic gitignore awareness.
    * Provides PCRE2 optional backend, binary file detection, config file support, and structured JSON output.

  Options:
    -C, --context <num>: Show <num> lines before and after each match.
    -t, --type <lang>: Restrict searches to files recognized for a language (see `rg --type-list`).
    -g, --glob <pattern>: Include or exclude files matching the glob pattern.
    --hidden: Search hidden files and directories.
    --json: Emit machine-readable JSON results for tooling.
    -i, --ignore-case: Case insensitive search.
    -w, --word-regexp: Only match whole words.

  Notes:
    * Home Manager module at modules/hm-apps/ripgrep.nix provides user-level configuration.
*/
_:
let
  RipgrepModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.ripgrep.extended;
    in
    {
      options.programs.ripgrep.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable ripgrep.";
        };

        package = lib.mkPackageOption pkgs "ripgrep" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.ripgrep = RipgrepModule;
}
