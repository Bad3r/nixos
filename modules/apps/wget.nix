/*
  Package: wget
  Description: GNU command-line utility for non-interactive network downloads.
  Homepage: https://www.gnu.org/software/wget/
  Documentation: https://www.gnu.org/software/wget/manual/wget.html
  Repository: https://git.savannah.gnu.org/cgit/wget.git

  Summary:
    * Fetches files over HTTP, HTTPS, and FTP with recursive mirroring and retry support.
    * Handles authentication, rate limiting, and timestamp-based syncing for automation tasks.

  Options:
    -r -np <url>: Recursively download a site without ascending to parent directories.
    --continue <url>: Resume partially downloaded files.
    --limit-rate=1M <url>: Throttle download bandwidth to a fixed rate.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.wget.extended;
  WgetModule = {
    options.programs.wget.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = lib.mdDoc "Whether to enable wget.";
      };

      package = lib.mkPackageOption pkgs "wget" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.wget = WgetModule;
}
