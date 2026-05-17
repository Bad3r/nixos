/*
  Package: naabu
  Description: Fast SYN, CONNECT, and UDP port scanner.
  Homepage: https://github.com/projectdiscovery/naabu
  Documentation: https://docs.projectdiscovery.io/opensource/naabu/overview
  Repository: https://github.com/projectdiscovery/naabu

  Summary:
    * Enumerates open ports for hosts, IPs, CIDRs, and ASNs with SYN, CONNECT, and UDP scanning.
    * Streams results into tools such as httpx and supports JSON, CSV, and plain output.

  Options:
    -host <value>: Hosts to scan ports for.
    -list, -l <file>: File containing hosts to scan.
    -port, -p <ports>: Ports to scan, including ranges and UDP ports.
    -top-ports, -tp <set>: Built-in top-port set to scan.
    -exclude-cdn, -ec: Skip full port scans for CDN/WAF targets.
    -rate <value>: Packets to send per second.
    -j, -json: Write output in JSON Lines format.
    -silent: Display only results.

  Notes:
    * `modules/custom-overlays/naabu.nix` upgrades older nixpkgs channels to upstream v2.6.1.
*/
_:
let
  NaabuModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.naabu.extended;
    in
    {
      options.programs.naabu.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable naabu.";
        };

        package = lib.mkPackageOption pkgs "naabu" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.naabu = NaabuModule;
}
