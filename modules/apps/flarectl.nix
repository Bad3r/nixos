/*
  Package: flarectl
  Description: Command-line interface for managing Cloudflare resources via cloudflare-go.
  Homepage: https://github.com/cloudflare/cloudflare-go/tree/master/cmd/flarectl
  Documentation: https://github.com/cloudflare/cloudflare-go/tree/master/cmd/flarectl#readme
  Repository: https://github.com/cloudflare/cloudflare-go

  Summary:
    * Executes Cloudflare API operations for zones, DNS records, firewall rules, and accounts from the terminal.
    * Supports credential loading from environment variables or config files to script Cloudflare workflows.

  Options:
    --zone <domain>: Target a specific zone when listing or modifying DNS records (`flarectl --zone example.com dns list`).
    --account <id>: Scope requests to a particular Cloudflare account when multiple are available.
    --config <file>: Provide API tokens and defaults via a YAML configuration file.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.flarectl.extended;
  FlarectlModule = {
    options.programs.flarectl.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = lib.mdDoc "Whether to enable flarectl.";
      };

      package = lib.mkPackageOption pkgs "flarectl" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.flarectl = FlarectlModule;
}
