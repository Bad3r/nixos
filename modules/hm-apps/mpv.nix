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
    --vo <gpu|drm>: Video output driver selection.
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
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.mpv = {
          enable = true;
          package = pkgs.mpv;
          config = {
            osc = "yes"; # On Screen Controller
            pause = "no"; # Start the player in paused state
            ytdl = "yes"; # Enable youtube-dl
            ytdl-format = "best"; # Use the best format available
            ytdl-raw-options = "cookies-from-browser=floorp";
            profile = "high-quality"; # gpu-hq is deprecated
            vo = "gpu";
            gpu-api = "opengl"; # force stable interop; avoids NVDEC freeze with current NVIDIA stack
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
            "[" = "add speed 0.1";
            "]" = "add speed -0.1";
          };

          scripts = with pkgs.mpvScripts; [
            mpv-cheatsheet
            mpris # use standard media keys
            autoload # auto load previous/next file in playlist
            reload # reload streamed file when stuck buffering
          ];
        };

        # Add Lua script to block images (store under XDG config)
        xdg.configFile."mpv/scripts/block-images.lua".text = ''
          local blocked_extensions = {
            jpg = true, jpeg = true, png = true,
            webp = true, bmp = true, tiff = true,
            gif = true
          }

          mp.add_hook("on_preloaded", 10, function()
            local path = mp.get_property("path") or ""
            local ext = path:match("%.([^%.]+)$") or ""
            if blocked_extensions[ext:lower()] then
              mp.msg.warn("Blocking image file: " .. path)
              mp.commandv("playlist-remove", "current")
            end
          end)
        '';
      };
    };
}
