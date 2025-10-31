/*
  Package: gimp
  Description: GNU Image Manipulation Program.
  Homepage: https://www.gimp.org/
  Documentation: https://docs.gimp.org/2.10/en/
  Repository: https://gitlab.gnome.org/GNOME/gimp

  Summary:
    * Professional-grade raster graphics editor with layers, masks, filters, and plugin ecosystem for photo editing and compositing.
    * Supports advanced color management, GEGL-based processing, and extensibility via Python Scheme plug-ins.

  Options:
    --batch <script>: Execute Scheme or Python batch scripts headlessly.
    --no-interface <file>: Process files without loading the full UI.
    --verbose: Emit plugin and initialization logs for debugging.
    --new-instance: Start a separate instance rather than reusing the existing session.

  Example Usage:
    * `gimp` — Open the full-featured UI for image editing.
    * `gimp --batch '(file-png-save RUN-NONINTERACTIVE 0 "input.png" "output.png" 0 9 1 1 1)'` — Run automated conversions inside scripts.
    * `gimp --no-interface --batch "(python-fu-fog RUN-NONINTERACTIVE \"input.xcf\" \"output.png\" 5 0.5 0.8)" --batch "(gimp-quit 0)"` — Apply filters headlessly in CI.
*/

{
  flake.homeManagerModules.apps.gimp =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.gimp.extended;
    in
    {
      options.programs.gimp.extended = {
        enable = lib.mkEnableOption "GNU Image Manipulation Program.";
      };

      config = lib.mkIf cfg.enable {
        home.packages = [ pkgs.gimp ];
      };
    };
}
