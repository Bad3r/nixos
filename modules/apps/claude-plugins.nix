/*
  Package: claude-plugins
  Description: CLI tool for managing Claude Code plugins and marketplaces.
  Homepage: https://github.com/Kamalnrf/claude-plugins
  Documentation: https://github.com/Kamalnrf/claude-plugins/blob/main/packages/cli/README.md
  Repository: https://github.com/Kamalnrf/claude-plugins

  Summary:
    * Plugin manager for Claude Code providing access to plugins through a centralized registry.
    * Manages plugin marketplaces, installation, and activation state in ~/.claude/plugins/.

  Options:
    install <id>: Install a plugin or marketplace from the registry.
    list: List installed plugins and marketplaces.
    enable <name>: Enable a disabled plugin.
    disable <name>: Disable an active plugin.

  Notes:
    * Package sourced from llm-agents.nix flake (github:numtide/llm-agents.nix).
    * For skill installation, use skills-installer (separate package) with --client flag.
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
