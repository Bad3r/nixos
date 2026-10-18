/*
  Package: codex
  Description: Lightweight coding agent that runs in your terminal.
  Homepage: https://github.com/openai/codex
  Documentation: https://github.com/openai/codex#readme
  Repository: https://github.com/openai/codex

  Summary:
    * Provides an interactive TUI that orchestrates code edits, tests, and tooling via OpenAI models with sandboxed execution and approvals.
    * Supports non-interactive automation, session resume, Model Context Protocol servers, and configurable instructions through config.toml and AGENTS.md.

  Options:
    --model <model>: Select the OpenAI model to use (default: o4-mini).
    --approval-policy <mode>: Override the approval policy (suggest, auto-edit, full-auto).
    --sandbox-mode <mode>: Adjust the sandbox level for commands (docker, seatbelt, none).

  Notes:
    * Package sourced from llm-agents.nix flake (github:numtide/llm-agents.nix).
    * Home Manager installs a wrapper around `package` and manages the configuration (modules/agents/codex/home.nix).
*/
{ inputs, ... }:
{
  flake.nixosModules.apps.codex =
    { lib, pkgs, ... }:
    let
      defaultPackage = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.codex;
    in
    {
      options.programs.codex.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable codex.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = defaultPackage;
          defaultText = lib.literalExpression "defaultPackage";
          description = "The codex package to use.";
        };
      };
    };
}
