/*
  Package: ripgrep-all
  Description: Ripgrep, but also search in PDFs, E-Books, Office documents, zip, tar.gz, and more.
  Homepage: https://github.com/phiresky/ripgrep-all
  Documentation: https://github.com/phiresky/ripgrep-all#readme
  Repository: https://github.com/phiresky/ripgrep-all

  Summary:
    * Extends ripgrep (`rga`) to index and search through binary and structured formats by delegating to format-aware extractors.
    * Supports caching, pre-processing, and multi-tool pipelines to search PDFs, Office docs, images, videos, and data stores.

  Options:
    --type pdf|epub|docx: Limit extraction to specific document types.
    --files-with-matches <pattern>: List files that contain matches without printing lines.
    --rga-cache-dir <dir>: Override the cache directory used for extracted text.
    --type-list: Show the available extractors and whether required tools are installed (`rga-preproc --type-list`).

  Example Usage:
    * `rga "encryption" docs/` -- Find references across PDFs, Markdown, Office documents, and archives.
    * `rga --type epub --context 2 "machine learning" ~/ebooks` -- Search eBooks with contextual lines.
    * `rga-preproc --type-list` -- Verify extractor dependencies such as `pdftotext`, `pandoc`, and `ffmpeg`.
*/

{
  flake.homeManagerModules.apps.ripgrep-all =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.ripgrep-all.extended;
    in
    {
      options.programs.ripgrep-all.extended = {
        enable = lib.mkEnableOption "Ripgrep, but also search in PDFs, E-Books, Office documents, zip, tar.gz, and more.";
      };

      config = lib.mkIf cfg.enable {
        home.packages = [ pkgs.ripgrep-all ];
      };
    };
}
