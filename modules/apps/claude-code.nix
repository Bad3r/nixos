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
let
  # Maps each Claude Code LSP plugin key → the NixOS programs.<name> option name.
  # Used both to declare lspPlugins options and to generate priority-1050 enable
  # overrides when a plugin is active, beating the catalog's 1100 false without
  # suppressing a catalog true (we only ever assert true here, never false).
  lspPluginProgramMap = {
    "clangd-lsp" = "clangd";
    "csharp-lsp" = "csharp-ls";
    "gopls-lsp" = "gopls";
    "jdtls-lsp" = "jdt-language-server";
    "kotlin-lsp" = "kotlin-language-server";
    "lua-lsp" = "lua-language-server";
    "php-lsp" = "intelephense";
    "pyright-lsp" = "pyright";
    "rust-analyzer-lsp" = "rust-analyzer";
    "swift-lsp" = "sourcekit-lsp";
    "typescript-lsp" = "typescript-language-server";
  };
in
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
              `programs.bun.extended.enable = true`; this module automatically
              imports the `bun` Home Manager app module when the bun install
              method is enabled. Binary lands at `$XDG_DATA_HOME/bun/bin/claude`.
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

        lspPlugins = lib.mapAttrs (
          pluginKey: _:
          lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = ''
              Whether to enable the ${pluginKey} Claude Code LSP plugin and ensure
              its binary is installed. When true, overrides the catalog at priority
              1050 so the package is installed even if apps-enable.nix says false.
            '';
          }
        ) lspPluginProgramMap;

        extraPlugins = lib.mkOption {
          type = lib.types.attrsOf lib.types.bool;
          default = {
            "frontend-design@claude-plugins-official" = true;
          };
          example = lib.literalExpression ''
            {
              "frontend-design@claude-plugins-official" = true;
              "some-other-plugin@some-marketplace" = false;
            }
          '';
          description = ''
            Additional non-LSP Claude Code plugins to enable, keyed by the
            `"<plugin>@<marketplace>"` identifier used in
            `~/.claude/settings.json`'s `enabledPlugins`. Set an entry to
            `false` to keep the key registered but disabled, or override the
            whole attrset to drop defaults entirely. The marketplace named in
            the suffix must already be registered in
            `~/.claude/plugins/known_marketplaces.json` for the entry to take
            effect.
          '';
        };
      };

      config = lib.mkIf cfg.enable (
        lib.mkMerge (
          [
            {
              environment.systemPackages = lib.optional cfg.installMethods.nix.enable cfg.package;
              nixpkgs.allowedUnfreePackages = lib.optionals cfg.installMethods.nix.enable [ "claude-code" ];
              # Import by Home Manager app key so import-tree resolves the module location.
              # The bun HM module owns BUN_INSTALL/PATH setup and the createBunDir DAG node.
              home-manager.extraAppImports = lib.mkAfter (lib.optional cfg.installMethods.bun.enable "bun");

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
            }
          ]
          ++ lib.mapAttrsToList (
            pluginKey: programName:
            lib.mkIf cfg.lspPlugins.${pluginKey} {
              programs.${programName}.extended.enable = lib.mkOverride 1050 true;
            }
          ) lspPluginProgramMap
        )
      );
    };
}
