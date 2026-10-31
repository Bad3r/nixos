/*
  Package: media-toolchain
  Description: Convenience bundle installing the project's standard multimedia tools (ffmpeg, ImageMagick, Ghostscript, GStreamer plugins).
  Homepage: https://github.com/Bad3r/nixos
  Documentation: https://github.com/Bad3r/nixos
  Repository: https://github.com/Bad3r/nixos

  Summary:
    * Ensures transcoding, thumbnail generation, and document rendering utilities are available in the environment.
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
        ];
      };
    };
in
{
  flake.nixosModules.apps."media-toolchain" = MediaToolchainModule;
}
