/*
  Package: mpv (with helper scripts)
  Description: High-quality media player with bundled scripts for thumbnails, Jellyfin integration, and convenience utilities.
  Homepage: https://mpv.io/
  Documentation: https://mpv.io/manual/stable/
  Repository: https://github.com/mpv-player/mpv

  Summary:
    * Installs mpv along with thumbnail preview (`thumbfast`), shader presets, cheat sheet overlay, `open-in-mpv`, and `jellyfin-mpv-shim` for streaming servers.
    * Supports advanced playback via GPU acceleration, scripting (Lua/Python), configurable keybindings, and remote control via JSON IPC or `mpv` sockets.

  Options:
    mpv <file|url>: Play media from local files or network sources.
    --profile=<name>: Apply predefined profiles (e.g. `--profile=high-quality`).
    --script=<path>: Load additional scripts at runtime.
    mpv --idle=yes --input-ipc-server=/tmp/mpvsocket: Expose a control socket for remote commands.
    jellyfin-mpv-shim: Launch the Jellyfin controller for direct playback through mpv.

  Example Usage:
    * `mpv --hwdec=auto movie.mkv` — Play a video with automatic hardware decoding.
    * `mpv https://www.youtube.com/watch?v=dQw4w9WgXcQ` — Stream content directly using youtube-dl integration.
    * `jellyfin-mpv-shim` — Pair with a Jellyfin server to stream media through mpv.
*/

_:
let
  MpvModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.mpv.extended;
    in
    {
      options.programs.mpv.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable mpv media player.";
        };

        package = lib.mkPackageOption pkgs "mpv" { };

        extraScripts = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = with pkgs; [
            mpvScripts.thumbfast
            mpvScripts.mpv-cheatsheet
          ];
          description = lib.mdDoc ''
            mpv scripts to install.

            Included by default:
            - thumbfast: Fast thumbnail preview
            - mpv-cheatsheet: Keybinding overlay
          '';
          example = lib.literalExpression "with pkgs; [ mpvScripts.thumbfast ]";
        };

        extraPackages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = with pkgs; [
            mpv-shim-default-shaders
            open-in-mpv
          ];
          description = lib.mdDoc ''
            Additional mpv-related tools.

            Included by default:
            - mpv-shim-default-shaders: Shader presets
            - open-in-mpv: Browser integration
          '';
          example = lib.literalExpression "with pkgs; [ jellyfin-mpv-shim ]";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ] ++ cfg.extraScripts ++ cfg.extraPackages;
      };
    };
in
{
  flake.nixosModules.apps.mpv = MpvModule;
}
