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
          config = {
            osc = "yes"; # On Screen Controller
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

          scripts = with pkgs.mpvScripts; [
            # mpv-cheatsheet
            mpris # use standard media keys
            # autoload # auto load previous/next file in playlist
            reload # reload streamed file when stuck buffering
          ];
        };

        xdg.configFile = {
          "mpv/scripts/ytdlp-cookies.lua".text = ''
            -- Resolve which browser yt-dlp should read cookies from.
            -- Priority: MPV_YTDLP_BROWSER env var > $BROWSER env var.
            -- Set MPV_YTDLP_BROWSER="" to disable cookie passthrough entirely.
            -- Skips silently if cookies-from-browser is already in ytdl-raw-options (CLI flag).

            local function resolve_browser()
              local override = os.getenv("MPV_YTDLP_BROWSER")
              if override ~= nil then return override end
              local xdg = os.getenv("BROWSER")
              if xdg and xdg ~= "" then
                return (xdg:match("^(%S+)") or xdg)
              end
              return ""
            end

            local existing = mp.get_property("ytdl-raw-options") or ""
            if not existing:find("cookies%-from%-browser") then
              local browser = resolve_browser()
              if browser ~= "" then
                mp.msg.info("ytdlp-cookies: cookies-from-browser=" .. browser)
                mp.set_property("ytdl-raw-options-append", "cookies-from-browser=" .. browser)
              else
                mp.msg.verbose("ytdlp-cookies: no browser resolved, skipping cookie passthrough")
              end
            end
          '';

          "mpv/hwdec-codecs.conf".text = ''
            hwdec-codecs-append=mpeg2video
            hwdec-codecs-append=mpeg4
            hwdec-codecs-append=msmpeg4v2
            hwdec-codecs-append=msmpeg4v3
          '';

          # Lua hook to drop image files from mixed-content playlists before decoding
          "mpv/scripts/block-images.lua".text = ''
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
    };
}
