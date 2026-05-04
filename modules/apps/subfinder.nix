/*
  Package: subfinder
  Description: Passive subdomain discovery tool for reconnaissance and bug bounty workflows.
  Homepage: https://github.com/projectdiscovery/subfinder
  Documentation: https://docs.projectdiscovery.io/tools/subfinder
  Repository: https://github.com/projectdiscovery/subfinder

  Summary:
    * Aggregates valid subdomains for a target by querying a configurable set of passive sources without touching the target infrastructure.
    * Integrates with the ProjectDiscovery ecosystem via stdin input and structured output suited to chaining with httpx, dnsx, and nuclei.

  Options:
    -d <domain>: Target domain(s) to enumerate (comma-separated).
    -dL <file>: File containing a list of domains to enumerate.
    -all: Use all available passive sources for broader coverage at the cost of speed.
    -recursive: Use only recursive sources for deep enumeration.
    -o <file>: Write results to the specified output file.
    -silent: Print only discovered subdomains.
    -config <file>: Path to a YAML configuration file (default `$HOME/.config/subfinder/provider-config.yaml`).
*/
_:
let
  SubfinderModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.subfinder.extended;
    in
    {
      options.programs.subfinder.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable subfinder.";
        };

        package = lib.mkPackageOption pkgs "subfinder" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.subfinder = SubfinderModule;
}
