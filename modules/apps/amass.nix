/*
  Package: amass
  Description: OWASP attack surface mapping toolkit for DNS enumeration and infrastructure discovery.
  Homepage: https://owasp.org/www-project-amass/
  Documentation: https://github.com/owasp-amass/amass/wiki/User-Guide
  Repository: https://github.com/OWASP/Amass

  Summary:
    * Enumerates subdomains and related infrastructure by combining OSINT, brute forcing, ASN mapping, and reverse DNS.
    * Stores findings in a project workspace for later pivoting, graphing, and differential analysis.

  Options:
    amass intel -d <domain>: Gather candidate infrastructure intelligence for a target domain.
    amass enum -d <domain>: Run subdomain enumeration using configured sources and brute forcing.
    amass db -show -d <domain>: Inspect previously collected names and infrastructure from the local Amass database.
*/
_:
let
  AmassModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.amass.extended;
    in
    {
      options.programs.amass.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable amass.";
        };

        package = lib.mkPackageOption pkgs "amass" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.amass = AmassModule;
}
