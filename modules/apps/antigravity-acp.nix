/*
  Package: antigravity-acp
  Description: Official ACP server for Google Antigravity's AI coding agent.
  Homepage: https://antigravity.google/docs/ide/extensions
  Documentation: https://antigravity.google/docs
  Repository: nil

  Summary:
    * Provides `agy_acp_server` and `localharness_external` from nixpkgs for Agent Client Protocol integrations.
*/
_:
let
  AntigravityAcpModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."antigravity-acp".extended;
    in
    {
      options.programs."antigravity-acp".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable antigravity-acp.";
        };

        package = lib.mkPackageOption pkgs "antigravity-acp" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [ "antigravity-acp" ];
  flake.nixosModules.apps."antigravity-acp" = AntigravityAcpModule;
}
