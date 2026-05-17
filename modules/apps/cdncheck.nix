/*
  Package: cdncheck
  Description: Identify CDN, cloud, and WAF technologies for DNS names or IP addresses.
  Homepage: nil
  Documentation: nil
  Repository: https://github.com/projectdiscovery/cdncheck

  Summary:
    * Detects CDN, cloud, and WAF providers from DNS or IP network address input.
    * Supports provider match and filter modes for focused recon workflows.

  Options:
    -i, -input <value>: List of IP or DNS inputs to process.
    -cdn / -cloud / -waf: Display only the selected technology class.
    -mcdn, -match-cdn <value>: Match hosts against specified CDN providers.
    -mcloud, -match-cloud <value>: Match hosts against specified cloud providers.
    -mwaf, -match-waf <value>: Match hosts against specified WAF providers.
    -j, -jsonl: Write output in JSON Lines format.
    -silent: Only display results.
*/
_:
let
  CdncheckModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.cdncheck.extended;
    in
    {
      options.programs.cdncheck.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable cdncheck.";
        };

        package = lib.mkPackageOption pkgs "cdncheck" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.cdncheck = CdncheckModule;
}
