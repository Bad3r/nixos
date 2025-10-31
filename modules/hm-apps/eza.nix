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
    --long: Show extended metadata including permissions, owners, and timestamps.
    --tree: Render directory trees recursively with indentation.
    --git: Display Git status for tracked files.
    --icons: Show icons (requires nerd font) alongside filenames.
    --sort=size: Sort entries by size; other keys include time, name, extension.

  Example Usage:
    * `eza --long --git` — Inspect working tree state with detailed metadata and Git indicators.
    * `eza --tree --level=2 ~/projects` — Browse nested folders with a limited depth tree view.
    * `eza --icons --sort=size Downloads` — List downloads with icons sorted by file size.
*/

{
  flake.homeManagerModules.apps.eza =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.eza.extended;
    in
    {
      options.programs.eza.extended = {
        enable = lib.mkEnableOption "Modern, maintained replacement for ls.";
      };

      config = lib.mkIf cfg.enable {
        home.packages = [ pkgs.eza ];
      };
    };
}
