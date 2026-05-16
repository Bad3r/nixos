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

{ config, ... }:
let
  mpvScripts = config.flake.lib.homeManager.mpvScripts;
in
{
  flake.homeManagerModules.apps.mpv =
    {
      osConfig,
      config,
      lib,
      pkgs,
      ...
    }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "mpv" "extended" "enable" ] false osConfig;
      extraScripts = lib.attrByPath [ "programs" "mpv" "extended" "extraScripts" ] [ ] osConfig;
      localScripts = mpvScripts { inherit lib pkgs; };
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
            # Drop sub-pos from persisted watch-later state; modernz manages it dynamically.
            watch-later-options-remove = "sub-pos";
            cache = "yes";
            volume = 60;
            border = "no";
            keepaspect-window = "no"; # don't lock window size to video aspect ratio
          };

          # Disable mpv-image-viewer's status-line by default. The script renders a
          # persistent ASS overlay (filename, [N/M] playlist position, [WxH] dimensions)
          # and never auto-hides. Only the img profile re-enables it for image viewing.
          scriptOpts.status_line.enabled = "no";

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

          profiles = {
            "vid" = {
              profile-desc = "skip image files in playlists";
              script-opts = "playlist_filter-mode=block-images";
            };
            "img" = {
              profile-desc = "image viewer: skip non-image files, hold each image until manual advance, loop playlist";
              script-opts = "playlist_filter-mode=images-only,status_line-enabled=yes";
              image-display-duration = "inf";
              loop-playlist = "inf";
              osd-level = 0;
            };
          };

          scripts =
            (with pkgs.mpvScripts; [
              modernz # OSC replacement; works with thumbfast for seek previews
              mpv-cheatsheet-ng # overlay listing all active keybindings; open with ?
              mpris # use standard media keys
              # autoload # auto load previous/next file in playlist
              reload # reload streamed file when stuck buffering
            ])
            ++ (with pkgs.mpvScripts.mpv-image-viewer; [
              freeze-window # prevent window close after the last image
              image-positioning # pan, zoom, and rotate controls for images
              status-line # image dimensions and zoom level overlay
            ])
            ++ [
              localScripts.scripts.playlistFilter
              localScripts.scripts.ytdlpCookies
            ]
            ++ extraScripts;
        };

        home.packages =
          let
            mpv = config.programs.mpv.finalPackage;
          in
          [
            (pkgs.writeShellScriptBin "mpv-vid" ''
              exec ${mpv}/bin/mpv --profile=vid "$@"
            '')
            (pkgs.writeShellScriptBin "mpv-img" ''
              exec ${mpv}/bin/mpv --profile=img "$@"
            '')
          ];
      };
    };
}
