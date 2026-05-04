/*
  Package: dnsenum
  Description: Multi-purpose DNS enumeration toolkit for reconnaissance.
  Homepage: nil
  Documentation: nil
  Repository: https://github.com/fwaeytens/dnsenum

  Summary:
    * Gathers DNS host records (A, NS, MX), attempts AXFR transfers, performs Google subdomain scraping, and brute-forces names from a wordlist.
    * Resolves discovered hosts in parallel, walks PTR records via netranges, and emits XML reports for downstream tooling.

  Options:
    --enum: Convenience switch equivalent to `--threads 5 -s 15 -w` for combined enumeration.
    --dnsserver <server>: Force queries against a specific resolver instead of system DNS.
    -f <file>: Subdomain wordlist used for brute-force name generation.
    -r: Recurse into NS records returned during the scan.
    --noreverse: Skip reverse-lookup expansion of discovered network ranges.
    -o <file>: Write the run as an XML report.
    -t <seconds>: TCP/UDP DNS query timeout per request.
    -p <pages> / -s <results>: Limit Google scraping to the given page count and result cap.
*/
_:
let
  DnsenumModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.dnsenum.extended;
    in
    {
      options.programs.dnsenum.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable dnsenum.";
        };

        package = lib.mkPackageOption pkgs "dnsenum" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.dnsenum = DnsenumModule;
}
