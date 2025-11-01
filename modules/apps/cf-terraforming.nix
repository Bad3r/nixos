/*
  Package: cf-terraforming
  Description: Cloudflare utility that generates Terraform configurations from existing resources.
  Homepage: https://github.com/cloudflare/cf-terraforming
  Documentation: https://github.com/cloudflare/cf-terraforming#readme
  Repository: https://github.com/cloudflare/cf-terraforming

  Summary:
    * Authenticates with the Cloudflare API to export DNS, firewall, and account resources as HCL.
    * Accelerates migrations from manual dashboards to infrastructure-as-code managed with Terraform.

  Options:
    --config <file>: Load Cloudflare credentials and defaults from a YAML configuration file.
    --zone-id <id>: Restrict exports to a specific zone instead of enumerating all accessible zones.
    --tf-version <version>: Emit Terraform configuration pinned to the specified language version.
*/
_:
let
  CfTerraformingModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."cf-terraforming".extended;
    in
    {
      options.programs.cf-terraforming.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable cf-terraforming.";
        };

        package = lib.mkPackageOption pkgs "cf-terraforming" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.cf-terraforming = CfTerraformingModule;
}
