/*
  Package: dragon-drop
  Description: Lightweight drag-and-drop bridge that makes files from the terminal or clipboard available to graphical apps.
  Homepage: https://github.com/mwh/dragon
  Documentation: https://github.com/mwh/dragon#readme
  Repository: https://github.com/mwh/dragon

  Summary:
    * Spawns a small draggable icon that represents files piped in via stdin or passed as arguments, enabling drag-and-drop from terminal sessions.
    * Operates on both X11 and Wayland (when running under XWayland), providing a quick way to hand off paths to editors, browsers, or chat clients.

  Options:
    dragon-drop <file> [<file>...]: Offer the provided files for drag-and-drop into another application.
    dragon-drop -t <target>: Restrict the allowed MIME target (defaults to text/uri-list for file drops).
    xdragon …: Symlinked entry point identical to dragon-drop for compatibility with older workflows.

  Example Usage:
    * `dragon-drop report.pdf` — Present a draggable handle for report.pdf.
    * `printf '%s\n' screenshot.png | dragon-drop` — Pipe paths from another command and drag the resulting selection.
    * `dragon-drop ~/Downloads/*.png` — Collect multiple assets and drop them into a browser upload dialog.
*/

{
  flake.nixosModules.apps."dragon-drop" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."dragon-drop" ];
    };
}
