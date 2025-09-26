/*
  Package: eza
  Description: Modern, maintained replacement for ls.
  Homepage: https://eza.rocks/
  Documentation: https://eza.rocks/guide/
  Repository: https://github.com/eza-community/eza

  Summary:
    * Provides colorized, Git-aware directory listings with optional icons, tree views, and file metadata columns.
    * Implements modern terminal UX with configurable presets, sort options, human-readable sizes, and recursive depth limits.

  Options:
    eza --long: Show extended metadata including permissions, owners, and timestamps.
    eza --tree: Render directory trees recursively with indentation.
    eza --git: Display Git status for tracked files.
    eza --icons: Show icons (requires nerd font) alongside filenames.
    eza --sort=size: Sort entries by size; other keys include time, name, extension.

  Example Usage:
    * `eza --long --git` — Inspect working tree state with detailed metadata and Git indicators.
    * `eza --tree --level=2 ~/projects` — Browse nested folders with a limited depth tree view.
    * `eza --icons --sort=size Downloads` — List downloads with icons sorted by file size.
*/

{
  flake.homeManagerModules.apps.eza =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.eza ];
    };
}
