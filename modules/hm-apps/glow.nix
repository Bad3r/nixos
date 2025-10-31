/*
  Package: glow
  Description: Terminal Markdown renderer with theme-aware previews, pager streaming, and remote fetching support.
  Homepage: https://github.com/charmbracelet/glow
  Documentation: https://github.com/charmbracelet/glow#readme
  Repository: https://github.com/charmbracelet/glow

  Summary:
    * Provides a TUI Markdown preview that respects ANSI colors and stylings like tables and code fences.
    * Ships a JSON export mode and directory browser so you can pipe rendered Markdown into other tooling.
*/

{
  flake.homeManagerModules.apps.glow =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.glow.extended;
    in
    {
      options.programs.glow.extended = {
        enable = lib.mkEnableOption "Terminal Markdown renderer with theme-aware previews, pager streaming, and remote fetching support.";
      };

      config = lib.mkIf cfg.enable {
        home.packages = [ pkgs.glow ];
      };
    };
}
