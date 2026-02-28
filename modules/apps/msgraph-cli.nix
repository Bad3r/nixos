/*
  Package: msgraph-cli
  Description: Microsoft Graph CLI.
  Homepage: https://github.com/microsoftgraph/msgraph-cli
  Documentation: https://github.com/microsoftgraph/msgraph-cli#readme
  Repository: https://github.com/microsoftgraph/msgraph-cli

  Summary:
    * Provides the `mgc` command-line interface for authenticating and calling Microsoft Graph endpoints from scripts and terminals.
    * Supports delegated and app-only authentication strategies for tenant automation workflows.

  Options:
    login: Sign in using the default device-code authentication flow.
    login --strategy InteractiveBrowser: Sign in with a browser-based delegated flow.
    login --strategy ClientCertificate: Authenticate non-interactively using an app registration and certificate.
*/
_:
let
  MsgraphCliModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."msgraph-cli".extended;
    in
    {
      options.programs."msgraph-cli".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable msgraph-cli.";
        };

        package = lib.mkPackageOption pkgs "msgraph-cli" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.msgraph-cli = MsgraphCliModule;
}
