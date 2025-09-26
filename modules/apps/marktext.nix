/*
  Package: marktext (with glow)
  Description: Electron-based Markdown editor with real-time preview and GitHub-flavored Markdown support; bundle also ships `glow` for terminal preview.
  Homepage: https://marktext.app/
  Documentation: https://github.com/marktext/marktext#readme
  Repository: https://github.com/marktext/marktext

  Summary:
    * Provides a cross-platform Markdown editor with live preview, split view, tabbed interface, and export to PDF/HTML.
    * Includes the `glow` terminal viewer for quick Markdown previews within shells, complementing the GUI editor.

  Options:
    marktext: Launch the desktop editor.
    marktext <file.md>: Open a specific Markdown file directly.
    glow <file.md>: Render Markdown in the terminal with styling.
    glow --pager/--style: Customize terminal presentation when viewing documents.

  Example Usage:
    * `marktext notes.md` — Edit a Markdown document with live preview and formatting tools.
    * `glow README.md` — View a project README in the terminal using the bundled CLI.
    * `glow --json doc.md | jq '.body'` — Export Markdown to JSON for further processing.
*/

{
  flake.nixosModules.apps.marktext =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        marktext
        glow
      ];
    };

}
