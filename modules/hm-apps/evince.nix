/*
  Package: evince
  Description: GNOME's document viewer.
  Homepage: https://apps.gnome.org/Evince/
  Documentation: https://help.gnome.org/users/evince/stable/
  Repository: https://gitlab.gnome.org/GNOME/evince

  Summary:
    * Opens PDF, PostScript, DjVu, DVI, and TIFF documents with search, annotations, form filling, and accessibility integrations.
    * Integrates with GNOME desktop features such as printing, dark mode, embedded thumbnails, and document history syncing.

  Options:
    --fullscreen: Start in full-screen presentation mode.
    --page-label=<label>: Jump directly to a labeled page when opening a document.
    --named-destination=<name>: Open a PDF named destination for precise navigation.
    --presentation: Begin a slide-friendly presentation view.

  Example Usage:
    * `evince design-review.pdf` -- View PDF documentation within GNOME or other Wayland/X11 sessions.
    * `evince --presentation roadmap.pdf` -- Present slides using Evince’s full-screen controls.
    * `evince --page-label=Appendix design-spec.pdf` -- Jump straight to tagged sections for quick reviews.
*/

{
  flake.homeManagerModules.apps.evince =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.evince.extended;
    in
    {
      options.programs.evince.extended = {
        enable = lib.mkEnableOption "GNOME's document viewer.";
      };

      config = lib.mkIf cfg.enable {
        home.packages = [ pkgs.evince ];
      };
    };
}
