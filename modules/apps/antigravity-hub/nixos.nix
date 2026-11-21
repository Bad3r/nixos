/*
  Package: antigravity-hub
  Description: Desktop environment for managing multiple autonomous agents across independent projects.
  Homepage: https://antigravity.google/
  Documentation: https://antigravity.google/docs
  Repository: nil

  Summary:
    * Provides the `antigravity` desktop app for running Google Antigravity agents across separate projects.
    * Ships the Electron app from the llm-agents.nix package, patched for NixOS.
*/
{ inputs, ... }:
let
  AntigravityHubModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."antigravity-hub".extended;
    in
    {
      options.programs."antigravity-hub".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable antigravity-hub.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.antigravity-hub;
          defaultText = lib.literalExpression "inputs.llm-agents.packages.\${system}.antigravity-hub";
          description = "The antigravity-hub package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."antigravity-hub" = AntigravityHubModule;
}
