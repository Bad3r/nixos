/*
  Package: playerctl
  Description: Command-line controller for MPRIS-compatible media players.
  Homepage: https://github.com/altdesktop/playerctl
  Documentation: https://github.com/altdesktop/playerctl#usage
  Repository: https://github.com/altdesktop/playerctl

  Summary:
    * Communicates with media players exposing the MPRIS DBus interface (Spotify, VLC, mpv) to play/pause, seek, and query metadata.
    * Supports monitoring playback events, targeting specific players, and scripting playback control in window manager keybindings.

  Options:
    playerctl play/pause/stop/next/previous: Control playback state.
    playerctl metadata [--format <fmt>]: Display track metadata with template support.
    playerctl --player <name>: Target specific players (comma-separated list).
    playerctl position <seconds>: Seek relative or absolute positions (e.g., `+10`, `5%`).
    playerctl status: Report current playback status.

  Example Usage:
    * `playerctl play-pause` — Toggle playback for the first active player.
    * `playerctl --player=spotify metadata --format '{{title}} by {{artist}}'` — Show the current Spotify track in a custom format.
    * `playerctl --player=mpv position +30` — Skip forward 30 seconds in mpv.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.playerctl.extended;
  PlayerctlModule = {
    options.programs.playerctl.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true; # Backward compatibility - TODO: flip to false in Phase 2
        description = lib.mdDoc "Whether to enable playerctl.";
      };

      package = lib.mkPackageOption pkgs "playerctl" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.playerctl = PlayerctlModule;
}
