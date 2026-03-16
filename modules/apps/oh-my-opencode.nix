/*
  Package: oh-my-opencode
  Description: Multi-model orchestration harness and plugin layer for OpenCode.
  Homepage: https://github.com/code-yeongyu/oh-my-openagent
  Documentation: https://github.com/code-yeongyu/oh-my-openagent#readme
  Repository: https://github.com/code-yeongyu/oh-my-openagent

  Summary:
    * Extends OpenCode with orchestration, background-task workflows, LSP tooling, MCP management, and additional agent capabilities.
    * Provides an install flow plus operational commands for running guarded OpenCode tasks and diagnosing local setup issues.

  Options:
    install: Install and configure oh-my-opencode with interactive setup.
    run [options] <message>: Run opencode with todo and background-task enforcement.
    doctor: Check installation health and diagnose issues.

  Notes:
    * Package sourced from llm-agents.nix flake (github:numtide/llm-agents.nix).
    * Upstream package metadata still uses the `oh-my-opencode` name while the upstream repository is `code-yeongyu/oh-my-openagent`.
*/
{ inputs, ... }:
let
  OhMyOpencodeModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."oh-my-opencode".extended;
    in
    {
      options.programs."oh-my-opencode".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable oh-my-opencode.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}."oh-my-opencode";
          defaultText = lib.literalExpression "inputs.llm-agents.packages.\${system}.\"oh-my-opencode\"";
          description = "The oh-my-opencode package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."oh-my-opencode" = OhMyOpencodeModule;
}
