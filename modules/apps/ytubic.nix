/*
  Package: ytubic
  Description: Fast, responsive YouTube Music desktop client.
  Homepage: nil
  Documentation: nil
  Repository: https://github.com/NUber-dev/YTubic

  Summary:
    * Provides a native desktop interface for YouTube Music with library, playlist, lyrics, and playback support.
    * Integrates with Linux media controls and desktop notifications.

  Options:
    ytubic: Launch the YouTube Music desktop application.

  Notes:
    * The nixpkgs package uses the packaged yt-dlp executable because the upstream PyInstaller download is not usable on NixOS.
*/
_:
let
  YtubicModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.ytubic.extended;
    in
    {
      options.programs.ytubic.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable ytubic.";
        };

        package = lib.mkPackageOption pkgs "ytubic" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.ytubic = YtubicModule;
}
