/*
  Package: claude-plugins
  Description: CLI tool for managing Claude Code plugins and agent skills.
  Homepage: https://github.com/Kamalnrf/claude-plugins
  Documentation: https://github.com/Kamalnrf/claude-plugins/blob/main/packages/cli/README.md
  Repository: https://github.com/Kamalnrf/claude-plugins

  Summary:
    * Unified plugin manager providing access to 11,989+ Claude Code plugins and 63,065+ agent skills through a centralized registry.
    * Multi-client support enabling skill installation across 15+ AI coding environments including Claude Code, Cursor, Windsurf, and VS Code.

  Options:
    --client <name>: Specifies target client (defaults to claude-code).
    --local, -l: Restricts installation to current directory only.
    install <plugin/skill>: Installs components from the registry.
    search [query]: Provides interactive terminal-based skill discovery.

  Notes:
    * Package sourced from llm-agents.nix flake (github:numtide/llm-agents.nix).
*/
{ inputs, ... }:
{
  flake.nixosModules.apps.claude-plugins =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.claude-plugins.extended;
    in
    {
      options.programs.claude-plugins.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable claude-plugins.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-plugins;
          defaultText = lib.literalExpression "inputs.llm-agents.packages.\${system}.claude-plugins";
          description = "The claude-plugins package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
}
