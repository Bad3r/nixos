/*
  Package: azd
  Description: Azure Developer CLI for provisioning and deploying application resources.
  Homepage: https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/
  Documentation: https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/reference
  Repository: https://github.com/Azure/azure-dev

  Summary:
    * Provides workflow-oriented commands for app lifecycle tasks, including template initialization, infrastructure provisioning, deployment, and teardown.
    * Supports environment management and CI/CD pipeline configuration for repeatable Azure application delivery.

  Options:
    init: Initialize a new app project from an Azure Developer CLI template.
    up: Provision infrastructure and deploy the application in a single workflow command.
    provision: Apply infrastructure-as-code changes without deploying application code.
*/
_:
let
  AzdModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.azd.extended;
    in
    {
      options.programs.azd.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable azd.";
        };

        package = lib.mkPackageOption pkgs "azd" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.azd = AzdModule;
}
