/*
  Package: krita
  Description: Free and open source painting application.
  Homepage: https://krita.org/
  Documentation: https://docs.krita.org/en/
  Repository: https://invent.kde.org/graphics/krita

  Summary:
    * Digital painting studio with brush engines, HDR painting, animation tools, and vector/bitmap layers.
    * Supports resource bundles, scripting with Python, and workflows tailored for illustration, comics, and concept art.

  Options:
    --canvas-only: Start in distraction-free canvas mode.
    --nosplash: Skip the splash screen on startup.
    --profile <icc>: Apply a specific color profile when opening.
    --export <file>: Export documents via command-line (works with additional `--export-filename`).

  Example Usage:
    * `krita` — Open the full interface for drawing and animation.
    * `krita --canvas-only` — Focus solely on the canvas during tablet sessions.
    * `krita --export animation.kra --export-filename animation.mp4` — Render an animation sequence from the CLI.
*/

{
  flake.homeManagerModules.apps.krita =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.krita ];
    };
}
