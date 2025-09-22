{
  flake.nixosModules.apps."media-toolchain" =
    { pkgs, lib, ... }:
    {
      environment.systemPackages = lib.mkAfter (
        with pkgs;
        [
          mpv
          stash
          ffmpeg-full
          ffmpegthumbnailer
          imagemagick
          ghostscript
        ]
        ++ (with pkgs.gst_all_1; [
          gst-libav
          gst-plugins-bad
          gst-plugins-good
          gst-plugins-ugly
          gst-vaapi
        ])
      );
    };

  flake.nixosModules.pc =
    { pkgs, lib, ... }:
    {
      environment.systemPackages = lib.mkAfter (
        with pkgs;
        [
          mpv
          stash
          ffmpeg-full
          ffmpegthumbnailer
          imagemagick
          ghostscript
        ]
        ++ (with pkgs.gst_all_1; [
          gst-libav
          gst-plugins-bad
          gst-plugins-good
          gst-plugins-ugly
          gst-vaapi
        ])
      );
    };
}
