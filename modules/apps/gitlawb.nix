/*
  Package: gitlawb
  Description: Sandboxed CLI for interacting with the decentralized gitlawb network.
  Homepage: https://gitlawb.com
  Documentation: https://docs.gitlawb.com
  Repository: nil

  Summary:
    * Provides the `gl` CLI and `git-remote-gitlawb` helper for creating identities, registering with gitlawb nodes, and cloning or pushing gitlawb repositories.

  Options:
    identity new: Generate an Ed25519 identity and DID for gitlawb.
    register: Register the local identity with a gitlawb node and save a bootstrap UCAN.
    repo create: Create a repository on the configured gitlawb node.
    mcp serve: Expose gitlawb tools over MCP for agent integrations.

  Notes:
    * Access is limited to the current workspace and `~/.gitlawb`.
*/
_:
let
  GitlawbModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.gitlawb.extended;
    in
    {
      options.programs.gitlawb.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable gitlawb.";
        };

        package = lib.mkPackageOption pkgs "gitlawb" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [ "gitlawb" ];
  flake.nixosModules.apps.gitlawb = GitlawbModule;
}
