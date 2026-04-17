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
          description = ''
            Whether this host uses claude-code. Configures Home Manager side
            (settings, skills, MCP merge). Requires at least one entry in
            `installMethods.*.enable` to also be true.
          '';
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = wrappedPackage;
          defaultText = lib.literalExpression "inputs.llm-agents.packages.\${system}.claude-code";
          description = "Claude Code package used when installMethods.nix.enable is true.";
        };

        installMethods = {
          nix.enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = ''
              Install claude-code via Nix (adds `cfg.package` to
              `environment.systemPackages`). Default install method.
            '';
          };

          bun.enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Install claude-code via `bun install -g @anthropic-ai/claude-code`
              during every Home Manager activation. Requires
              `programs.bun.extended.enable = true`. Binary lands at
              `$XDG_DATA_HOME/bun/bin/claude`.
            '';
          };
        };

        anyInstallEnabled = lib.mkOption {
          type = lib.types.bool;
          readOnly = true;
          default = cfg.enable && (cfg.installMethods.nix.enable || cfg.installMethods.bun.enable);
          description = ''
            Read-only. True if claude-code is enabled with at least one install
            method. Consumers can use this to check availability without
            enumerating individual install methods.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = lib.optional cfg.installMethods.nix.enable cfg.package;
        nixpkgs.allowedUnfreePackages = lib.optionals cfg.installMethods.nix.enable [ "claude-code" ];

        assertions = [
          {
            assertion = cfg.anyInstallEnabled;
            message = ''
              programs.claude-code.extended.enable = true, but no install method
              is enabled. Set one of:
                programs.claude-code.extended.installMethods.nix.enable = true;
                programs.claude-code.extended.installMethods.bun.enable = true;
              (typically in modules/<host>/apps-enable.nix)
            '';
          }
          {
            assertion = (!cfg.installMethods.bun.enable) || config.programs.bun.extended.enable;
            message = ''
              programs.claude-code.extended.installMethods.bun.enable requires
              programs.bun.extended.enable = true. Enable bun in your host's
              apps-enable.nix (e.g. modules/tpnix/apps-enable.nix:32 or
              modules/system76/apps-enable.nix:47) before enabling the bun
              install method for claude-code.
            '';
          }
        ];
      };
    };
}
