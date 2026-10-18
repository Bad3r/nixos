/*
  Package: gemini-cli
  Description: AI agent that brings the power of Gemini directly into your terminal.
  Homepage: https://github.com/google-gemini/gemini-cli
  Documentation: https://www.geminicli.com/docs/
  Repository: https://github.com/google-gemini/gemini-cli

  Summary:
    * Provides a terminal-first Gemini agent for code understanding, task automation, file operations, shell commands, and web tools.
    * Supports interactive sessions, non-interactive prompts, structured output, MCP servers, extensions, skills, and sandboxed execution.

  Options:
    -m, --model <model_name>: Select the Gemini model for the session.
    -p, --prompt <prompt>: Run a prompt in non-interactive mode.
    -s, --sandbox: Enable sandbox mode for the session.
    --approval-mode <mode>: Set tool approval behavior.
    --include-directories <paths>: Add up to five directories to the workspace.

  Notes:
    * Package sourced from llm-agents.nix flake (github:numtide/llm-agents.nix).
    * Home Manager module enables config surfaces while NixOS owns the package installation.
*/
{ inputs, ... }:
let
  GeminiCliModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."gemini-cli".extended;
    in
    {
      options.programs."gemini-cli".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable gemini-cli.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.gemini-cli;
          defaultText = lib.literalExpression "inputs.llm-agents.packages.\${system}.gemini-cli";
          description = "The gemini-cli package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."gemini-cli" = GeminiCliModule;
}
