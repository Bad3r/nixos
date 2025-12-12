/*
  Package: zoom-us
  Description: Video conferencing and web conferencing service with screen sharing and recording.
  Homepage: https://zoom.us/
  Documentation: https://support.zoom.us/
  Repository: https://github.com/NixOS/nixpkgs/tree/master/pkgs/applications/networking/instant-messengers/zoom-us

  Summary:
    * Full-featured video conferencing with HD video, audio, and screen sharing capabilities.
    * Supports virtual backgrounds, breakout rooms, recording, and live transcription.

  Options:
    --no-sandbox: Disable sandboxing if experiencing connection or audio issues (use with caution).
    --enable-wayland: Enable native Wayland support for better performance on Wayland compositors.
*/
_:
let
  ZoomModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.zoom-us.extended;
    in
    {
      options.programs.zoom-us.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable zoom-us.";
        };

        package = lib.mkPackageOption pkgs "zoom-us" { };
      };

      config = lib.mkIf cfg.enable {
        nixpkgs.allowedUnfreePackages = [ "zoom" ];

        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.zoom-us = ZoomModule;
}
