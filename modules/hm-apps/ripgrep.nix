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
*/
_: {
  flake.homeManagerModules.apps.ripgrep =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "ripgrep" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.ripgrep = {
          enable = true;
          package = null;
        };
      };
    };
}
