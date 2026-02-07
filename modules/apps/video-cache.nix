/*
  Package: video-cache
  Description: Build and maintain a cache of video file durations for filtering and playback.
  Homepage: https://github.com/vx/nixos
  Documentation: https://github.com/vx/nixos/tree/main/packages/video-cache

  Summary:
    * Scans directories for video files and caches their durations in TSV format.
    * Supports incremental updates: removes deleted files, adds new ones, skips cached.

  Options:
    --force: Clear cache and rescan all files.
    --quiet: Suppress progress bar and summary output.

  Notes:
    * Package defined in packages/video-cache/default.nix and exposed via overlay.
    * Cache stored at <video_dir>/.cache/video-durations.tsv.
    * Errors logged to <video_dir>/.cache/video-errors.log.
*/
_:
let
  VideoCacheModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.video-cache.extended;
    in
    {
      options.programs.video-cache.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable video-cache.";
        };

        package = lib.mkPackageOption pkgs "video-cache" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.video-cache = VideoCacheModule;
}
