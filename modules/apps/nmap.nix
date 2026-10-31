/*
  Package: nmap
  Description: Network exploration and security auditing utility for port scanning and service enumeration.
  Homepage: https://nmap.org/
  Documentation: https://nmap.org/book/
  Repository: https://svn.nmap.org/nmap

  Summary:
    * Performs flexible TCP/UDP port scans, OS detection, version probing, and scriptable service checks.
    * Includes Nmap Scripting Engine (NSE) for vulnerability detection and automation.

  Options:
    nmap -sV <target>: Detect open ports and service versions.
    nmap -sC -sV <target>: Run default scripts alongside version detection.
    nmap -Pn -A <target>: Aggressive scan with OS detection and traceroute when hosts ignore ICMP.
*/
_:
let
  NmapModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.nmap.extended;
    in
    {
      options.programs.nmap.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable nmap.";
        };

        package = lib.mkPackageOption pkgs "nmap" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.nmap = NmapModule;
}
