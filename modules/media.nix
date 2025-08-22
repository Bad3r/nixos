{

  flake.modules.nixos.pc =
    { pkgs, ... }:
    {
      environment.systemPackages =
        with pkgs;
        [
          mpv
          stash
          # Media processing
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
        ]);
    };
}
