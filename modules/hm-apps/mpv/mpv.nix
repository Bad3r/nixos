/*
  Package: mpv
  Description: General-purpose media player, fork of MPlayer and mplayer2.
  Homepage: https://mpv.io/
  Documentation: https://mpv.io/manual/stable/
  Repository: https://github.com/mpv-player/mpv

  Summary:
    * Provides a minimalist video player with extensive codec support, hardware decoding, and scriptability.
    * Supports youtube-dl integration, custom keybindings, and Lua/JavaScript scripting for automation.

  Options:
    --profile <name>: Apply a named profile from configuration.
    --hwdec <auto|vaapi|nvdec>: Select hardware decoding method.
    --vo <gpu-next|drm>: Video output driver selection.
    --ytdl-format <format>: Specify youtube-dl format preference.

  Example Usage:
    * `mpv video.mp4` -- Play a local video file.
    * `mpv https://youtube.com/watch?v=...` -- Stream video via youtube-dl integration.
    * `mpv --profile=high-quality movie.mkv` -- Apply high-quality profile for playback.
*/

_: {
  flake.homeManagerModules.apps.mpv =
    {
      osConfig,
      lib,
      pkgs,
      ...
    }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "mpv" "extended" "enable" ] false osConfig;
      extraScripts = lib.attrByPath [ "programs" "mpv" "extended" "extraScripts" ] [ ] osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.mpv = {
          enable = true;
          config = {
            osc = "no"; # disabled; modernz provides the OSC
            pause = "no"; # Start the player in paused state
            ytdl = "yes"; # Enable youtube-dl
            ytdl-format = "best"; # Use the best format available
            profile = "high-quality";
            vo = "gpu-next";
            hwdec = "auto";
            gpu-context = "auto"; # let mpv pick a supported context (x11/wayland)
            save-position-on-quit = "no";
            video-sync = "display-resample";
            interpolation = "yes";
            tscale = "oversample";
            cache = "yes";
            volume = 60;
            border = "no";
            keepaspect-window = "no"; # don't lock window size to video aspect ratio
          };

          bindings = {
            "q" = "quit";
            "j" = "seek 5";
            "k" = "seek -5";
            "h" = "seek 5";
            "l" = "seek -5";
            "n" = "playlist-next";
            "p" = "playlist-prev";
            "m" = "cycle mute";
            "v" = "cycle video";
            "a" = "cycle audio";
            "[" = "add speed -0.1";
            "]" = "add speed 0.1";
          };

          includes = [ "~~/hwdec-codecs.conf" ];

          scripts =
            (with pkgs.mpvScripts; [
              modernz # OSC replacement; works with thumbfast for seek previews
              mpv-cheatsheet-ng # overlay listing all active keybindings; open with ?
              mpris # use standard media keys
              # autoload # auto load previous/next file in playlist
              reload # reload streamed file when stuck buffering
            ])
            ++ extraScripts;
        };

        xdg.configFile = {
          "mpv/scripts/ytdlp-cookies.lua".source = ./scripts/ytdlp-cookies.lua;
          "mpv/hwdec-codecs.conf".source = ./hwdec-codecs.conf;
          "mpv/scripts/block-images.lua".source = ./scripts/block-images.lua;
        };
      };
    };
}
