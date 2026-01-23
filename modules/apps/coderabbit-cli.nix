/*
  Package: coderabbit-cli
  Description: CodeRabbit's terminal client for AI-powered code reviews and repository automation.
  Homepage: https://coderabbit.ai/
  Documentation: https://docs.coderabbit.ai/docs/cli
  Repository: https://github.com/coderabbitai/coderabbit-cli

  Summary:
    * Authenticates with CodeRabbit to request AI code reviews, summaries, and guidance for pull requests or local diffs.
    * Supports interactive terminal UI and plain text output suitable for CI pipelines or chat integrations.

  Options:
    coderabbit auth login: Sign into CodeRabbit and store credentials locally.
    coderabbit review --repo <path>: Generate an AI review for changes in the specified repository or diff.
    coderabbit update: Upgrade the CLI to the latest released version.

  Notes:
    * Package sourced from llm-agents.nix flake (github:numtide/llm-agents.nix).
*/
{ inputs, ... }:
{
  nixpkgs.allowedUnfreePackages = [ "coderabbit-cli" ];

  flake.nixosModules.apps."coderabbit-cli" =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."coderabbit-cli".extended;
    in
    {
      options.programs."coderabbit-cli".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable coderabbit-cli.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.coderabbit-cli;
          defaultText = lib.literalExpression "inputs.llm-agents.packages.\${system}.coderabbit-cli";
          description = "The coderabbit-cli package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
}
