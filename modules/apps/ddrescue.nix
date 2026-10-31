/*
  Package: ddrescue
  Description: GNU data recovery tool that clones damaged block devices while minimizing additional wear.
  Homepage: https://www.gnu.org/software/ddrescue/ddrescue.html
  Documentation: https://www.gnu.org/software/ddrescue/manual/ddrescue_manual.html
  Repository: nil

  Summary:
    * Copies data from failing disks to healthy targets using smart retry strategies and a persistent mapfile for resumable rescues.
    * Supports scraping, trimming, and reverse passes as well as fill and generate modes for advanced forensics workflows.

  Options:
    -r <n>: Retry failed blocks up to <n> additional passes (use `-1` for infinite retries).
    -d: Use direct I/O on the input device to bypass kernel caches.
    -n: Skip the scraping phase when you only want the initial fast copy.
    -R: Reverse the direction of all passes to read the tail of a device first.
    -m <mapfile>: Restrict the rescue domain to blocks marked as finished in another map.
*/
_:
let
  DdrescueModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.ddrescue.extended;
    in
    {
      options.programs.ddrescue.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable ddrescue.";
        };

        package = lib.mkPackageOption pkgs "ddrescue" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.ddrescue = DdrescueModule;
}
