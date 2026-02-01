/*
  Package: stash
  Description: Self-hosted web-based organizer and streaming server for adult media.
  Homepage: https://stashapp.cc/
  Documentation: https://docs.stashapp.cc/
  Repository: https://github.com/stashapp/stash

  Summary:
    * Scans, organizes, and streams local video/image libraries via web interface.
    * Supports metadata scraping, tagging, and performer/studio management.

  Options:
    -c, --config: Path to config file.
    --host: IP address to bind (default 0.0.0.0).
    --port: Port to serve from (default 9999).
    --nobrowser: Don't open browser window on launch.
    -u, --ui-location: Path to custom webui.
*/
_:
let
  StashModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.stash.extended;
    in
    {
      options.programs.stash.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable stash.";
        };

        package = lib.mkPackageOption pkgs "stash" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.stash = StashModule;
}
