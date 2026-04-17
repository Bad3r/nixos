/*
  Package: dirbuster
  Description: OWASP GUI for brute-forcing directories and files on web application servers.
  Homepage: https://sourceforge.net/projects/dirbuster/
  Documentation: https://wiki.owasp.org/index.php/Category:OWASP_DirBuster_Project
  Repository: nil

  Summary:
    * Launches the legacy OWASP DirBuster Swing interface with bundled wordlists for forced-browsing assessments.
    * Supports recursive discovery of directories and files by issuing threaded HTTP requests against a base target URL.

  Options:
    dirbuster: Launch the graphical interface and bundled wordlists.
    File -> Load a List: Select a custom wordlist instead of the packaged defaults.
    Start: Begin the configured forced-browsing scan against the target URL.
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
