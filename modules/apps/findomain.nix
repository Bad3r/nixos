/*
  Package: findomain
  Description: Fast cross-platform subdomain enumerator.
  Homepage: https://github.com/Findomain/Findomain
  Documentation: https://github.com/Findomain/Findomain/tree/master/docs
  Repository: https://github.com/Findomain/Findomain

  Summary:
    * Enumerates subdomains using Certificate Transparency logs and multiple public APIs.
    * Supports resolution, monitoring, database import/query, brute force, screenshots, and port scanning workflows.

  Options:
    -t, --target <target>: Target host to enumerate.
    -f, --file <file>: Use a file of subdomains as input.
    -r, --resolved: Show or write only resolved subdomains.
    -i, --ip: Show or write IP addresses for resolved subdomains.
    -o, --output: Write to an automatically generated output file.
    -u, --unique-output <file>: Write all target results to a specified file.
    -q, --quiet: Suppress informative messages.
    -c, --config <file>: Use a TOML, JSON, HJSON, INI, or YAML configuration file.
*/
_:
let
  FindomainModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.findomain.extended;
    in
    {
      options.programs.findomain.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable findomain.";
        };

        package = lib.mkPackageOption pkgs "findomain" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.findomain = FindomainModule;
}
