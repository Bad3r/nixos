/*
  Package: marp-cli
  Description: A CLI interface for Marp and Marpit based converters.
  Homepage: https://marp.app/
  Documentation: https://github.com/marp-team/marp-cli#readme
  Repository: https://github.com/marp-team/marp-cli

  Summary:
    * Renders Marp Markdown decks to HTML (default), PDF, PPTX, or PNG/JPEG image files.
    * Provides a watcher and a presentation server for previewing slide decks during authoring.

  Options:
    -o <file>: Write output to the given path; the extension selects the converter.
    --pdf, --pptx: Force PDF or PowerPoint output regardless of the output filename.
    --image <png|jpeg>: Convert only the first slide page into a single image file.
    --images <png|jpeg>: Convert every slide page into separate image files.
    -w, --watch: Re-render automatically when input Markdown or theme files change.
    -s, --server: Serve the input directory as a slide deck index over HTTP.
    -p, --preview: Open a preview window after conversion (requires a desktop environment).
    --theme <name|path>: Apply a built-in theme name or a custom CSS file to the deck.
    --engine <module>: Replace the default Marpit engine with a custom JavaScript module.
*/
_:
let
  MarpCliModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."marp-cli".extended;
    in
    {
      options.programs."marp-cli".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable marp-cli.";
        };

        package = lib.mkPackageOption pkgs "marp-cli" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.marp-cli = MarpCliModule;
}
