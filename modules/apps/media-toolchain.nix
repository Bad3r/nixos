/*
  Package: media-toolchain
  Description: Convenience bundle installing the project's standard multimedia tools (mpv, Stash, ffmpeg, ImageMagick, Ghostscript, GStreamer plugins).
  Homepage: https://github.com/vx/nixos
  Documentation: https://github.com/vx/nixos
  Repository: https://github.com/vx/nixos

  Summary:
    * Ensures media playback, transcoding, thumbnail generation, and document rendering utilities are available in the environment.
    * Includes GStreamer plugin sets (good/bad/ugly/libav/vaapi) for broad codec coverage alongside ffmpeg-full and supporting tools.

  Options:
    mpv: Full-featured media player with hardware acceleration.
    ffmpeg: Command-line transcoder for audio/video conversion.
    stash: Media server/organizer CLI utilities (per package defaults).
    imagemagick/ghostscript: Image and PDF manipulation tools.

  Example Usage:
    * `mpv video.mkv` — Playback media with Vulkan/VAAPI acceleration from the toolchain.
    * `ffmpeg -i input.mov -c:v libx264 output.mp4` — Transcode video using ffmpeg-full.
    * `gst-inspect-1.0 | grep vaapi` — Verify GStreamer VAAPI plugins are installed.
*/
_:
let
  MediaToolchainModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."media-toolchain".extended;
    in
    {
      options.programs."media-toolchain".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable media toolchain bundle.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = with pkgs; [
          mpv
          ffmpeg-full
          imagemagick
          ghostscript
          # GStreamer plugins
          gst_all_1.gstreamer
          gst_all_1.gst-plugins-base
          gst_all_1.gst-plugins-good
          gst_all_1.gst-plugins-bad
          gst_all_1.gst-plugins-ugly
          gst_all_1.gst-libav
          gst_all_1.gst-vaapi
        ];
      };
    };
in
{
  flake.nixosModules.apps."media-toolchain" = MediaToolchainModule;
}
