/*
  Package: audiness
  Description: CLI tool to interact with Nessus.
  Homepage: nil
  Documentation: nil
  Repository: https://github.com/audius/audiness

  Summary:
    * Provides helper commands for managing Nessus folders, policies, scans, servers, and software.
    * Uses the Nessus API instead of the web interface.

  Options:
    --access-key: Nessus API access key; also read from ACCESS_KEY.
    --secret-key: Nessus API secret key; also read from SECRET_KEY.
    --url: Nessus instance URL; also read from URL and defaults to https://localhost:8834.
    folders: Manage Nessus folders.
    policies: Manage Nessus policies.
    scans: Manage Nessus scans.
    server: Manage Nessus servers.
    software: Manage Nessus software.

  Notes:
    * Generate API keys in Nessus before using the CLI.
    * Use an SSH port forward when the Nessus instance is hosted elsewhere.
*/
_:
let
  audinessModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.audiness.extended;
    in
    {
      options.programs.audiness.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable audiness.";
        };

        package = lib.mkPackageOption pkgs "audiness" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.audiness = audinessModule;
}
