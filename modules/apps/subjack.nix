/*
  Package: subjack
  Description: DNS takeover scanner for identifying hijackable subdomains.
  Homepage: https://github.com/haccer/subjack
  Documentation: https://github.com/haccer/subjack#usage
  Repository: https://github.com/haccer/subjack

  Summary:
    * Tests known domains and subdomains for takeover conditions such as dangling CNAMEs, stale cloud A records, dangling NS delegations, AXFR exposure, and email-related DNS takeovers.
    * Fits recon pipelines after discovery tools such as subfinder, amass, or assetfinder and should be followed by manual verification of positive findings.

  Options:
    -d <domain>: Single domain to check.
    -w <file>: File containing domains or subdomains to scan.
    -t <count>: Number of concurrent worker threads.
    -timeout <seconds>: Connection timeout per request.
    -ssl: Force HTTPS requests.
    -a: Send requests to every URL, not only hosts with identified CNAMEs.
    -ns: Check nameserver takeover conditions.
    -ar: Check stale A records.
    -axfr: Check for zone transfers.
    -mail: Check SPF include and MX takeover conditions.
    -o <file>: Write text or JSON results.
*/
_:
let
  SubjackModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.subjack.extended;
    in
    {
      options.programs.subjack.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable subjack.";
        };

        package = lib.mkPackageOption pkgs "subjack" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.subjack = SubjackModule;
}
