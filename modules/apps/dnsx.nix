/*
  Package: dnsx
  Description: Fast and multi-purpose DNS toolkit for resolving and probing large host lists.
  Homepage: https://github.com/projectdiscovery/dnsx
  Documentation: https://docs.projectdiscovery.io/tools/dnsx
  Repository: https://github.com/projectdiscovery/dnsx

  Summary:
    * Performs concurrent DNS queries (A, AAAA, CNAME, MX, NS, PTR, SOA, TXT, AXFR) using user-supplied resolvers and retry logic.
    * Streams hosts from stdin and emits structured output, making it a drop-in stage between subfinder, httpx, and nuclei.

  Options:
    -l <file>: List of subdomains or hosts to resolve.
    -d <domain>: Domain to bruteforce when paired with `-w` wordlist.
    -r <file>: List of DNS resolvers to query (default uses public resolvers).
    -a / -aaaa / -cname / -ns / -txt / -mx / -ptr / -soa: Query specific record types.
    -resp-only: Show only the resolved response without echoing the input.
    -silent: Display only results, suppressing the banner and stats.
    -json: Emit JSON-formatted output for downstream consumption.
*/
_:
let
  DnsxModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.dnsx.extended;
    in
    {
      options.programs.dnsx.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable dnsx.";
        };

        package = lib.mkPackageOption pkgs "dnsx" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.dnsx = DnsxModule;
}
