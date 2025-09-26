/*
  Package: vlc
  Description: Versatile open-source multimedia player and framework supporting numerous codecs and streaming protocols.
  Homepage: https://www.videolan.org/vlc/
  Documentation: https://wiki.videolan.org/Documentation:VLC/
  Repository: https://code.videolan.org/videolan/vlc

  Summary:
    * Plays audio/video files, DVDs, network streams, and webcams with support for transcoding, recording, and playlist management.
    * Includes command-line interface (`cvlc`), HTTP streaming, Chromecast output, filter plugins, and hardware acceleration options.

  Options:
    vlc <media>: Launch GUI to play media files or streams.
    cvlc <media>: Start headless playback or streaming from the command line.
    vlc --fullscreen --play-and-exit: Auto-play in fullscreen and quit when finished.
    vlc --sout <stream>: Configure streaming/transcoding outputs.

  Example Usage:
    * `vlc movie.mkv` — Play a local video with hardware acceleration depending on platform.
    * `cvlc http://example.com/stream --intf rc` — Control VLC via remote control interface for automation.
    * `vlc video.mp4 --sout '#transcode{vcodec=h264,acodec=aac}:std{access=file,mux=mp4,dst=output.mp4}'` — Transcode content to MP4.
*/

{
  flake.nixosModules.apps.vlc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.vlc ];
    };

}
