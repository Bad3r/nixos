{
  nixpkgs.allowedUnfreePackages = [
    "spotify"
    "logseq"
  ];

  flake.modules.nixos.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        spotify
        logseq
        # Media processing
        ffmpeg-full
        ffmpegthumbnailer
        imagemagick
        ghostscript
      ] ++ (with pkgs.gst_all_1; [
        gst-libav
        gst-plugins-bad
        gst-plugins-good
        gst-plugins-ugly
        gst-vaapi
      ]);
    };
}
