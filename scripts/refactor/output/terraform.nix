/*
  Package: terraform
  Description: Infrastructure-as-code CLI for provisioning resources across cloud providers.
  Homepage: https://www.terraform.io/
  Documentation: https://developer.hashicorp.com/terraform/docs
  Repository: https://github.com/hashicorp/terraform

  Summary:
    * Executes declarative plans that create, update, and destroy infrastructure safely and repeatably.
    * Supports hundreds of providers with state management, modules, and policy enforcement integrations.

  Options:
    -var 'key=value': Inject or override input variables during `terraform plan` and `terraform apply`.
    -target=resource: Limit operations to specific resources for incremental changes.
    -auto-approve: Skip interactive confirmation when applying or destroying infrastructure.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.terraform.extended;
  TerraformModule = {
    options.programs.terraform.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true; # Backward compatibility - TODO: flip to false in Phase 2
        description = lib.mdDoc "Whether to enable terraform.";
      };

      package = lib.mkPackageOption pkgs "terraform" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.terraform = TerraformModule;
}
