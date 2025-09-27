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
  flake.nixosModules.apps.terraform =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.terraform ];
    };
}
