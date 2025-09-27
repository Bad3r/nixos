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

{
  flake.nixosModules.apps."cf-terraforming" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."cf-terraforming" ];
    };
}
