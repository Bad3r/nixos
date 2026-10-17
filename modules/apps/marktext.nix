/*
  Package: marktext
  Description: Electron-based Markdown editor with real-time preview and GitHub-flavored Markdown support.
  Homepage: https://marktext.app/
  Documentation: https://github.com/marktext/marktext#readme
  Repository: https://github.com/marktext/marktext

  Summary:
    * Provides a cross-platform Markdown editor with live preview, split view, tabbed interface, and export to PDF/HTML.

  Options:
    marktext: Launch the desktop editor.
    marktext <file.md>: Open a specific Markdown file directly.

  Example Usage:
    * `marktext notes.md` -- Edit a Markdown document with live preview and formatting tools.
*/

_:
let
  MarktextModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.marktext.extended;
    in
    {
      options.programs.marktext.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable MarkText editor.";
        };

        package = lib.mkPackageOption pkgs "marktext" { };

        extraPackages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
          description = "Additional packages to install alongside MarkText.";
          example = lib.literalExpression "with pkgs; [ pandoc ]";
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
