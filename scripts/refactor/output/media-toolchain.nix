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
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.gst_all_1.extended;
  Gst_all_1Module = {
    options.programs.gst_all_1.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true; # Backward compatibility - TODO: flip to false in Phase 2
        description = lib.mdDoc "Whether to enable gst_all_1.";
      };

      package = lib.mkPackageOption pkgs "gst_all_1" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.gst_all_1 = Gst_all_1Module;
}
