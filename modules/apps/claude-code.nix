/*
  Package: claude-code
  Description: Anthropic's Claude Code CLI for agentic coding in the terminal.
  Homepage: https://docs.anthropic.com/en/docs/claude-code/overview
  Documentation: https://docs.anthropic.com/en/docs/claude-code/overview
  Repository: https://github.com/anthropics/claude-code

  Summary:
    * Provides a terminal client that connects to Claude for iterative coding, planning, and troubleshooting sessions.
    * Supports worktree context ingestion so Claude can read, diff, and suggest updates within git repositories.

  Options:
    -p, --print: Non-interactive output mode for scripting.
    --add-dir: Additional directories to allow tool access to.
    --allowedTools: Comma-separated list of tool names to allow.
    --model: Override the default model for the session.

  Notes:
    * Package sourced from llm-agents.nix flake (github:numtide/llm-agents.nix).
    * Configuration managed by Home Manager module (modules/hm-apps/claude-code.nix).
*/
{ inputs, ... }:
{
  nixpkgs.allowedUnfreePackages = [ "claude-code" ];

  flake.nixosModules.apps.claude-code =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.claude-code.extended;

      basePackage = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;

      wrappedPackage = basePackage.overrideAttrs (old: {
        postFixup = (old.postFixup or "") + ''
          wrapProgram $out/bin/claude \
            --set DISABLE_AUTOUPDATER 1 \
            --set CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC 1 \
            --set DISABLE_NON_ESSENTIAL_MODEL_CALLS 1 \
            --set DISABLE_TELEMETRY 1 \
            --set DISABLE_INSTALLATION_CHECKS 1
        '';
      });
    in
    {
      options.programs.claude-code.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable claude-code.";
        };

        installPackage = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to install the claude-code package via Nix. Set to false to manage the binary externally (e.g., via bun).";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = wrappedPackage;
          defaultText = lib.literalExpression "inputs.llm-agents.packages.\${system}.claude-code";
          description = "The claude-code package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = lib.mkIf cfg.installPackage [ cfg.package ];
      };
    };
}
