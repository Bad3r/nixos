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

{
  flake.nixosModules.apps.normcap =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        normcap
      ];
    };
}
