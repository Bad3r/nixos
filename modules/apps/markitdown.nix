/*
  Package: markitdown
  Description: Python tool for converting files and office documents to Markdown.
  Homepage: nil
  Documentation: nil
  Repository: https://github.com/microsoft/markitdown

  Summary:
    * Converts PDF, Word, PowerPoint, Excel, images, audio, HTML, CSV, JSON, XML, ZIP, EPubs, and YouTube URLs to Markdown.
    * Extensible via plugins; optionally integrates with Azure Document Intelligence and Azure Content Understanding for enhanced OCR and extraction.

  Options:
    -o <file>: Write output to a file instead of stdout.
    -d: Enable Azure Document Intelligence for conversion.
    -e <endpoint>: Azure Document Intelligence endpoint URL.
    --use-plugins: Enable installed plugins during conversion.
    --list-plugins: List available installed plugins.
    --use-cu: Use Azure Content Understanding for conversion.
    --cu-endpoint <endpoint>: Azure Content Understanding endpoint URL.
*/
_:
let
  MarkitdownModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.markitdown.extended;
    in
    {
      options.programs.markitdown.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable markitdown.";
        };

        package = lib.mkPackageOption pkgs [ "python3Packages" "markitdown" ] { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.markitdown = MarkitdownModule;
}
