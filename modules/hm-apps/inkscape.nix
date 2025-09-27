/*
  Package: inkscape
  Description: Vector graphics editor.
  Homepage: https://inkscape.org/
  Documentation: https://inkscape.org/learn/docs/
  Repository: https://gitlab.com/inkscape/inkscape

  Summary:
    * Professional SVG authoring environment with bezier editing, layers, filters, and path operations for illustrations and UI assets.
    * Integrates with numerous import/export formats, live path effects, extensions, and scripting via Python.

  Options:
    --export-type=png <file.svg>: Export vector artwork to PNG.
    --batch-process <files>: Process multiple files without opening the UI.
    --select=<id>: Focus a specific object by ID on startup.
    --verb=<action>: Invoke classic verbs for automated transformations (1.x compatibility).

  Example Usage:
    * `inkscape logo.svg` — Edit scalable vector graphics with layers and path editing tools.
    * `inkscape --export-type=pdf brochure.svg` — Generate a print-ready PDF directly from CLI.
    * `inkscape --batch-process --actions="file-open:icons.svg;export-filename:icons.png;export-do;file-close"` — Automate asset exports in CI.
*/

{
  flake.homeManagerModules.apps.inkscape =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.inkscape ];
    };
}
