/*
  Package: azure-cli
  Description: Next generation multi-platform command line experience for Azure.
  Homepage: https://learn.microsoft.com/en-us/cli/azure/what-is-azure-cli
  Documentation: https://learn.microsoft.com/en-us/cli/azure/
  Repository: https://github.com/Azure/azure-cli

  Summary:
    * Provides a unified `az` interface for provisioning, operating, and automating Azure resources from local shells and CI pipelines.
    * Supports Azure AD authentication flows, extension-based service coverage, and structured output for scripting.

  Options:
    login: Authenticate to Azure using browser, device code, or service principal flows.
    account set --subscription <id|name>: Select the active subscription used by subsequent commands.
    --query <JMESPath>: Filter command responses client-side before rendering output.
*/
_:
let
  AzureCliModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."azure-cli".extended;
    in
    {
      options.programs."azure-cli".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable azure-cli.";
        };

        package = lib.mkPackageOption pkgs "azure-cli" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.azure-cli = AzureCliModule;
}
