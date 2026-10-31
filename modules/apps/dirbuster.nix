/*
  Package: dirbuster
  Description: OWASP GUI for brute-forcing directories and files on web application servers.
  Homepage: https://sourceforge.net/projects/dirbuster/
  Documentation: https://wiki.owasp.org/index.php/Category:OWASP_DirBuster_Project
  Repository: https://sourceforge.net/p/dirbuster/code/

  Summary:
    * Launches the legacy OWASP DirBuster Swing interface with bundled wordlists for forced-browsing assessments.
    * Supports recursive discovery of directories and files by issuing threaded HTTP requests against a base target URL.
*/
_:
let
  DirbusterModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.dirbuster.extended;
    in
    {
      options.programs.dirbuster.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable dirbuster.";
        };

        package = lib.mkPackageOption pkgs "dirbuster" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.dirbuster = DirbusterModule;
}
