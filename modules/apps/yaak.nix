/*
  Package: yaak
  Description: Desktop API client for organizing and executing REST, GraphQL, and gRPC requests.
  Homepage: https://yaak.app/
  Documentation: https://yaak.app/
  Repository: https://github.com/mountain-loop/yaak

  Summary:
    * Organize and execute REST, GraphQL, gRPC, WebSocket, and Server Sent Events requests in an offline-first client.
    * Supports encrypted secrets, Git-based workspace syncing, and imports from Postman, Insomnia, and OpenAPI.
*/
_:
let
  YaakModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.yaak.extended;
    in
    {
      options.programs.yaak.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable yaak.";
        };

        package = lib.mkPackageOption pkgs "yaak" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.yaak = YaakModule;
}
