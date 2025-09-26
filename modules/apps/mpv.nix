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

{
  flake.nixosModules.apps.mpv =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        mpv
        mpvScripts.thumbfast
        mpv-shim-default-shaders
        mpvScripts.mpv-cheatsheet
        open-in-mpv
        jellyfin-mpv-shim
      ];
    };

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        mpv
        mpvScripts.thumbfast
        mpv-shim-default-shaders
        mpvScripts.mpv-cheatsheet
        open-in-mpv
        jellyfin-mpv-shim
      ];
    };
}
