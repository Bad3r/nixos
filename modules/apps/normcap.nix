/*
  Package: normcap
  Description: Screenshot-to-text utility that recognizes text and copies it to the clipboard.
  Homepage: https://github.com/dynobo/normcap
  Documentation: https://github.com/dynobo/normcap#readme

  Summary:
    * Launches directly into selection mode for quick OCR snips.
    * Supports X11 and Wayland backends with clipboard integration.
    * Provides optional system tray indicator and history view.
*/

_:
let
  NormcapModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.normcap.extended;
    in
    {
      options.programs.normcap.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable normcap screenshot OCR utility.";
        };

        package = lib.mkPackageOption pkgs "normcap" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.normcap = NormcapModule;
}
