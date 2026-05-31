/*
  Package: antigravity-cli
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
  AntigravityCliModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."antigravity-cli".extended;
    in
    {
      options.programs."antigravity-cli".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable antigravity-cli.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.antigravity-cli;
          defaultText = lib.literalExpression "inputs.llm-agents.packages.\${system}.antigravity-cli";
          description = "The antigravity-cli package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [ "antigravity-cli" ];

  flake.nixosModules.apps."antigravity-cli" = AntigravityCliModule;
}
