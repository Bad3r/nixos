{

  flake.nixosModules.pc =
    { pkgs, lib, ... }:
    {
      # Add media toolchain after other package lists, to avoid surprising overrides
      environment.systemPackages = lib.mkAfter (
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
        ])
      );
    };
}
