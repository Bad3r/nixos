/*
  Package: bitwarden-cli
  Description: Secure and free password manager for all of your devices.
  Homepage: https://bitwarden.com
  Documentation: https://bitwarden.com/help/cli/
  Repository: https://github.com/bitwarden/clients

  Summary:
    * Provides command-line access to Bitwarden vault login, sync, unlock, and item retrieval workflows.
    * Supports automation-friendly session handling for scripts that need secrets from an existing Bitwarden account.

  Options:
    login: Authenticate the CLI against a Bitwarden account or self-hosted instance.
    unlock: Unlock the local encrypted vault and print a session token for follow-up commands.
    sync: Refresh the local vault cache from the remote Bitwarden service.
    get: Retrieve an item, password, attachment, or template from the vault.
*/
_:
let
  BitwardenCliModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."bitwarden-cli".extended;
    in
    {
      options.programs.bitwarden-cli.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable bitwarden-cli.";
        };

        package = lib.mkPackageOption pkgs "bitwarden-cli" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.bitwarden-cli = BitwardenCliModule;
}
