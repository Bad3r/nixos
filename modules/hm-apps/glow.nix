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
    { pkgs, ... }:
    {
      home.packages = [ pkgs.glow ];
    };
}
