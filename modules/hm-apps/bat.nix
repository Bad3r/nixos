/*
  Package: bat
  Description: Syntax-highlighted `cat` alternative with Git-aware paging and theming.
  Homepage: https://github.com/sharkdp/bat
  Documentation: https://github.com/sharkdp/bat#usage
  Repository: https://github.com/sharkdp/bat

  Summary:
    * Prints files with syntax highlighting, line numbers, Git integration, and automatic paging via `less`.
    * Supports multiple themes, custom highlighting assets, and convenient diff/line filtering switches.

  Options:
    bat --style=plain,numbers: Control decorations such as line numbers, grid, and header.
    bat --paging=never|always|auto: Override interaction with the pager.
    bat --line-range <start>:<end>: Show only the specified lines.
    bat --list-themes: Enumerate installed highlight themes.
    bat --diff: Highlight diff hunks passed on stdin with inline change markers.

  Example Usage:
    * `bat README.md` — Preview a Markdown file with syntax highlighting and pager integration.
    * `bat --style=plain --paging=never script.sh` — Emit raw highlighted output directly to stdout.
    * `git diff | bat --diff` — Colorize Git diff output with syntax-aware highlighting.
*/

{
  flake.homeManagerModules.apps.bat =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.bat ];
    };
}
