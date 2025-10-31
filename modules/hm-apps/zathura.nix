/*
  Package: zathura
  Description: Highly customizable and functional PDF viewer.
  Homepage: https://pwmt.org/projects/zathura/
  Documentation: https://pwmt.org/projects/zathura/documentation/
  Repository: https://github.com/pwmt/zathura

  Summary:
    * Keyboard-first document viewer with plugin support for PDF, DjVu, PS, CB, and more via modular backends.
    * Offers Vim-like navigation, synctex integration for LaTeX, recoloring, bookmarks, and scriptable key bindings.

  Options:
    --page=<number>: Jump to a specific page number on startup.
    --config-dir=<dir>: Use an alternate configuration directory.
    --synctex-forward=<line:column:file>: Activate forward search from LaTeX editors.
    --fork: Daemonize the viewer, freeing the calling shell immediately.

  Example Usage:
    * `zathura thesis.pdf` — Navigate a PDF with keyboard-driven commands and minimal chrome.
    * `zathura --page=10 references.djvu` — Skip directly to cited sections in large documents.
    * `zathura --synctex-forward="123:5:main.tex" thesis.pdf` — Sync from a LaTeX editor into the viewer.
*/

{
  flake.homeManagerModules.apps.zathura =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.zathura.extended;
    in
    {
      options.programs.zathura.extended = {
        enable = lib.mkEnableOption "Highly customizable and functional PDF viewer.";
      };

      config = lib.mkIf cfg.enable {
        home.packages = [ pkgs.zathura ];
      };
    };
}
