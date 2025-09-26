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
    evince <file>: Launch the document viewer with a specific file.
    evince --fullscreen <file>: Start in full-screen presentation mode.
    evince --page-label=<label> <file>: Jump directly to a labeled page.
    evince --named-destination=<name> <file>: Open a PDF named destination for precise navigation.
    evince --presentation <file>: Begin a slide-friendly presentation view.

  Example Usage:
    * `evince design-review.pdf` — View PDF documentation within GNOME or other Wayland/X11 sessions.
    * `evince --presentation roadmap.pdf` — Present slides using Evince’s full-screen controls.
    * `evince --page-label=Appendix design-spec.pdf` — Jump straight to tagged sections for quick reviews.
*/

{
  flake.homeManagerModules.apps.evince =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.evince ];
    };
}
