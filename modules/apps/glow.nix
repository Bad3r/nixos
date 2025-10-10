/*
  Package: glow
  Description: Terminal markdown renderer with styled previews, pager mode, and theme selection.
  Homepage: https://github.com/charmbracelet/glow
  Documentation: https://github.com/charmbracelet/glow#readme
  Repository: https://github.com/charmbracelet/glow

  Summary:
    * Renders Markdown with selectable dark/light themes directly in the terminal or pager.
    * Supports local and remote sources, TUI navigation, and export to plaintext or JSON for further tooling.

  Options:
    glow <path>: Render a Markdown file with the current style.
    glow --pager: Follow edits live in a scrollable preview.
    glow --style <dark|light>: Override the automatic theme choice.
    glow list --local: Browse cached documents managed by glow.
*/

{
  flake.nixosModules.apps.glow =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.glow ];
    };
}
