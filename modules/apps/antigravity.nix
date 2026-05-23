/*
  Package: antigravity
  Description: CLI for Google Antigravity, an agentic development platform.
  Homepage: https://antigravity.google/
  Documentation: https://antigravity.google/cli
  Repository: nil

  Summary:
    * Provides the `agy` CLI for Google Antigravity workflows from the terminal.
    * Supports interactive sessions, non-interactive prompts, workspace directory additions, sandboxed execution, and plugin management.

  Options:
    -p, --print: Run a single prompt non-interactively and print the response.
    -i, --prompt-interactive: Run an initial prompt interactively and continue the session.
    --add-dir: Add a directory to the workspace.
    --sandbox: Run with terminal sandbox restrictions enabled.
    plugin: Manage plugins.

  Notes:
    * Package sourced from llm-agents.nix flake (github:numtide/llm-agents.nix).
    * Package is unfree and must remain in `nixpkgs.allowedUnfreePackages`.
*/
{ inputs, ... }:
let
  AntigravityModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.antigravity.extended;
    in
    {
      options.programs.antigravity.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable antigravity.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.antigravity;
          defaultText = lib.literalExpression "inputs.llm-agents.packages.\${system}.antigravity";
          description = "The antigravity package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [ "antigravity" ];

  flake.nixosModules.apps.antigravity = AntigravityModule;
}
