/*
  Package: ripgrep
  Description: Utility that combines the usability of The Silver Searcher with the raw speed of grep.
  Homepage: https://github.com/BurntSushi/ripgrep
  Documentation: https://github.com/BurntSushi/ripgrep/blob/master/GUIDE.md
  Repository: https://github.com/BurntSushi/ripgrep

  Summary:
    * High-performance recursive search tool with regex support, smart case matching, and ignore-file awareness.
    * Provides PCRE2 optional backend, binary file detection, ripgrep config files, and structured output controls.

  Options:
    rg <pattern> <paths>: Search for regex matches across files and directories.
    rg --type <lang>: Restrict searches to files recognized for a language (see `rg --type-list`).
    rg --files: List files that would be searched while honoring ignore rules.
    rg --hidden --glob '!target/*': Include hidden files but exclude glob patterns.
    rg --json: Emit machine-readable JSON results for tooling.

  Example Usage:
    * `rg TODO src` — Locate TODO comments throughout a codebase with default ignore rules.
    * `rg --type rust --line-number 'Result<'` — Search only Rust files and show matching line numbers.
    * `rg --hidden --glob '!node_modules/*' "apiKey"` — Inspect hidden configuration while excluding vendor directories.
*/

{
  flake.homeManagerModules.apps.ripgrep =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.ripgrep ];
    };
}
