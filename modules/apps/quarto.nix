/*
  Package: quarto
  Description: Open-source scientific and technical publishing system built on Pandoc.
  Homepage: https://quarto.org/
  Documentation: https://quarto.org/docs/guide/
  Repository: https://github.com/quarto-dev/quarto-cli

  Summary:
    * Renders computational documents authored in Markdown, Jupyter, or RMarkdown into HTML, PDF, DOCX, ePub, or revealjs presentations.
    * Provides project, preview, and publishing workflows for books, websites, manuscripts, and dashboards backed by Pandoc and Knitr/Jupyter engines.

  Options:
    render <input>: Render a single document or project to its configured output formats.
    preview <input>: Render and serve a document with live reload while editing.
    create <type> <name>: Scaffold a new project, document, or extension from a template.
    publish <provider>: Publish rendered output to providers such as Quarto Pub, GitHub Pages, Netlify, or Connect.
    check: Verify the local installation, including Pandoc, LaTeX, and Jupyter dependencies.
    install <type> <target>: Install extensions, formats, or TinyTeX into the current project or user scope.
    convert <input>: Convert between Quarto, Jupyter, and RMarkdown source representations.
*/
_:
let
  QuartoModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.quarto.extended;
    in
    {
      options.programs.quarto.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable quarto.";
        };

        package = lib.mkPackageOption pkgs "quarto" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.quarto = QuartoModule;
}
