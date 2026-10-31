/*
  Package: vlc
  Description: Versatile open-source multimedia player and framework supporting numerous codecs and streaming protocols.
  Homepage: https://www.videolan.org/vlc/
  Documentation: https://wiki.videolan.org/Documentation:VLC/
  Repository: https://code.videolan.org/videolan/vlc

  Summary:
    * Plays files, discs, network streams, and webcams, with transcoding, recording, and playlists.
    * Includes the headless `cvlc` interface, HTTP streaming, and Chromecast output.

  Options:
    vlc --fullscreen --play-and-exit: Auto-play in fullscreen and quit when finished.
    vlc --sout <stream>: Configure streaming/transcoding outputs.
*/
_:
let
  VlcModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.vlc.extended;
    in
    {
      options.programs.vlc.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable vlc.";
        };

        package = lib.mkPackageOption pkgs "vlc" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.vlc = VlcModule;
}
