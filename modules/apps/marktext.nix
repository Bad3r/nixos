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
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.marktext.extended;
  MarktextModule = {
    options.programs.marktext.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = lib.mdDoc "Whether to enable MarkText editor.";
      };

      package = lib.mkPackageOption pkgs "marktext" { };

      extraPackages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = with pkgs; [ glow ]; # Default extras
        description = lib.mdDoc ''
          Additional packages to install alongside MarkText.
          Includes glow for terminal Markdown preview.
        '';
        example = lib.literalExpression "with pkgs; [ glow pandoc ]";
      };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ] ++ cfg.extraPackages;
    };
  };
in
{
  flake.nixosModules.apps.marktext = MarktextModule;
}
