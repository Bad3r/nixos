/*
  Package: nbtscan
  Description: Utility for scanning networks for NetBIOS information.
  Homepage: https://github.com/resurrecting-open-source-projects/nbtscan
  Documentation: https://github.com/resurrecting-open-source-projects/nbtscan#readme
  Repository: https://github.com/resurrecting-open-source-projects/nbtscan

  Summary:
    * Sends NetBIOS status queries across IP ranges and reports names, logged-in users, and MAC addresses.
    * Supports human-readable, /etc/hosts, lmhosts, and script-friendly output formats.

  Options:
    -v: Print all names received from each host.
    -r: Use local UDP port 137 for scans.
    -s SEPARATOR: Emit script-friendly output with SEPARATOR between fields.
    -f FILENAME: Read IP addresses to scan from FILENAME or stdin with `-f -`.
*/
_:
let
  NbtscanModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.nbtscan.extended;
    in
    {
      options.programs.nbtscan.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable nbtscan.";
        };

        package = lib.mkPackageOption pkgs "nbtscan" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.nbtscan = NbtscanModule;
}
