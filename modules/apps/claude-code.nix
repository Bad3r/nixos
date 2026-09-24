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
    * Configuration managed by Home Manager module (modules/agents/claude-code/home-manager.nix).
*/
{ inputs, ... }:
let
  # Language server behind each LSP plugin. An enabledPlugins entry set to true in
  # modules/agents/claude-code/_plugins.nix enables its program at priority 1050,
  # above the apps-enable.nix baseline (1100); false leaves the baseline alone.
  lspPluginProgramMap = {
    "clangd-lsp" = "clangd";
    "csharp-lsp" = "csharp-ls";
    "gopls-lsp" = "gopls";
    "jdtls-lsp" = "jdt-language-server";
    "lua-lsp" = "lua-language-server";
    "php-lsp" = "intelephense";
    "pyright-lsp" = "pyright";
    "rust-analyzer-lsp" = "rust-analyzer";
    "swift-lsp" = "sourcekit-lsp";
    "typescript-lsp" = "typescript-language-server";
  };

  inherit (import ../agents/claude-code/_plugins.nix) enabledPlugins;
in
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

      # Baked into the binary so a bare claude that bypasses ~/.local/bin/claude
      # still gets every _env.nix var.
      claudeEnv = import ../agents/claude-code/_env.nix;
      setFlags = lib.concatStringsSep " " (
        lib.mapAttrsToList (name: value: "--set ${name} ${lib.escapeShellArg value}") (
          builtins.removeAttrs claudeEnv.vars claudeEnv.launchOnly
        )
      );
      # Guarded, not --set: claude-rc lifts these for one launch, and a plain
      # --set here would be applied in-process where no outer wrapper reaches.
      launchOnlyRun = lib.optionalString (claudeEnv.launchOnly != [ ]) (
        "--run "
        + lib.escapeShellArg (
          "if [ -z \""
          + "$"
          + "{${claudeEnv.launchOnlyEscape}:-}\" ]; then export "
          + lib.concatStringsSep " " (
            map (name: "${name}=${lib.escapeShellArg claudeEnv.vars.${name}}") claudeEnv.launchOnly
          )
          + "; else unset ${lib.concatStringsSep " " claudeEnv.launchOnly}; fi"
        )
      );
      strippedNames = lib.attrNames claudeEnv.vars ++ [ "DISABLE_NON_ESSENTIAL_MODEL_CALLS" ];

      wrappedPackage = basePackage.overrideAttrs (old: {
        postFixup = (old.postFixup or "") + ''
          # The pinned llm-agents package wraps bin/claude before this hook, exporting
          # DISABLE_AUTOUPDATER and DISABLE_INSTALLATION_CHECKS and defaulting
          # DISABLE_NON_ESSENTIAL_MODEL_CALLS to 1, a name 2.1.281 never reads. Each
          # inner assignment of a name listed here is deleted so the flags below alone
          # decide it, and a leftover one fails the build.
          if [ "$(head -c 2 "$out/bin/claude")" != '#!' ]; then
            echo "claude-code: expected a textual inner wrapper at bin/claude; the pinned llm-agents wrapper shape changed" >&2
            exit 1
          fi
          for name in ${lib.escapeShellArgs strippedNames}; do
            sed -i "/^export $name=/d" "$out/bin/claude"
          done
          for name in ${lib.escapeShellArgs strippedNames}; do
            if grep -qF "$name=" "$out/bin/claude"; then
              echo "claude-code: inner wrapper still assigns $name after strip; the pinned llm-agents wrapper shape changed" >&2
              exit 1
            fi
          done
          wrapProgram $out/bin/claude \
            ${setFlags} ${launchOnlyRun}
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
            (settings, skills, MCP merge) regardless of whether any install
            method is enabled, so the binary may be managed outside Nix.
          '';
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = wrappedPackage;
          defaultText = lib.literalExpression "inputs.llm-agents.packages.\${system}.claude-code";
          description = "Claude Code package used when installMethods.nix.enable is true.";
        };

        externalBinary = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Absolute runtime path used by the Home Manager `~/.local/bin/claude`
            wrapper when both `installMethods.nix.enable` and
            `installMethods.bun.enable` are false. When null, the wrapper
            delegates to the Home Manager bun global path under XDG data home,
            so `programs.bun.extended.enable` must be true.
          '';
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
              on every Home Manager activation when the npm registry probe
              succeeds (curl against the latest-version endpoint with
              `--fail --max-time 5`). If the probe fails for any reason
              (DNS, TLS, HTTP 4xx/5xx, timeout), the install step is
              skipped, a warning is logged, and the existing binary (if any)
              at `$XDG_DATA_HOME/bun/bin/claude` is preserved. Requires
              `programs.bun.extended.enable = true`; this module automatically
              imports the `bun` Home Manager app module when the bun install
              method is enabled.
            '';
          };
        };
      };

      config = lib.mkIf cfg.enable (
        lib.mkMerge (
          [
            {
              environment.systemPackages = lib.optional cfg.installMethods.nix.enable cfg.package;
              # Import by Home Manager app key so import-tree resolves the module location.
              # The bun HM module owns BUN_INSTALL/PATH setup and the createBunDir DAG node.
              home-manager.extraAppImports = lib.mkAfter (lib.optional cfg.installMethods.bun.enable "bun");

              assertions =
                let
                  pluginKeys = lib.attrNames enabledPlugins;
                  malformedKeys = lib.filter (k: builtins.match ".+@.+" k == null) pluginKeys;
                  delegatesToBunGlobal =
                    (!cfg.installMethods.nix.enable) && (!cfg.installMethods.bun.enable) && cfg.externalBinary == null;
                in
                [
                  {
                    assertion = cfg.externalBinary == null || lib.hasPrefix "/" cfg.externalBinary;
                    message = ''
                      programs.claude-code.extended.externalBinary must be an absolute path.
                      The Home Manager wrapper and tweakcc shell-wrapper resolver require
                      a leading "/" for the selected target.
                    '';
                  }
                  {
                    assertion = (!cfg.installMethods.bun.enable) || config.programs.bun.extended.enable;
                    message = ''
                      programs.claude-code.extended.installMethods.bun.enable requires
                      programs.bun.extended.enable = true. Enable bun via the shared
                      baseline (modules/hosts/common/apps-enable.nix) or your host's
                      apps-enable.nix override before enabling the bun install method
                      for claude-code.
                    '';
                  }
                  {
                    assertion = (!delegatesToBunGlobal) || config.programs.bun.extended.enable;
                    message = ''
                      programs.claude-code.extended.externalBinary = null with both
                      claude-code install methods disabled delegates to the Home Manager
                      bun global path. Enable programs.bun.extended.enable, set
                      programs.claude-code.extended.externalBinary to an absolute path,
                      or enable one of the claude-code install methods.
                    '';
                  }
                  {
                    assertion = malformedKeys == [ ];
                    message = ''
                      enabledPlugins keys in modules/agents/claude-code/_plugins.nix must follow the
                      "<plugin>@<marketplace>" form (matching the suffix used in
                      ~/.claude/settings.json's enabledPlugins and the marketplace name
                      registered via extraKnownMarketplaces in
                      modules/agents/claude-code/_plugins.nix or
                      ~/.claude/plugins/known_marketplaces.json).
                      A key without an "@" suffix is silently ignored by Claude Code at
                      runtime.
                      Invalid keys: ${toString malformedKeys}
                    '';
                  }
                ];
            }
          ]
          ++ lib.mapAttrsToList (
            pluginKey: programName:
            lib.mkIf (enabledPlugins."${pluginKey}@claude-plugins-official" or false) {
              programs.${programName}.extended.enable = lib.mkOverride 1050 true;
            }
          ) lspPluginProgramMap
        )
      );
    };
}
