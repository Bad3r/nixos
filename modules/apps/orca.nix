/*
  Package: orca
  Description: Agent development environment for parallel coding agents.
  Homepage: https://onorca.dev/
  Documentation: https://www.onorca.dev/docs
  Repository: https://github.com/stablyai/orca

  Summary:
    * Runs coding agents in parallel Git worktrees.
    * Provides terminals, diffs, and a browser in a desktop application.

  Options:
    orca-ide: Launch the desktop application.
    orca: Manage Orca from the command line.

  Notes:
    * Package sourced from llm-agents.nix flake (github:Bad3r/llm-agents.nix).
*/
{ inputs, ... }:
{
  flake.nixosModules.apps.orca =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.orca.extended;
    in
    {
      options.programs.orca.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable the Orca desktop application and CLI.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.orca;
          defaultText = lib.literalExpression "inputs.llm-agents.packages.\${system}.orca";
          description = "The Orca package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
}
