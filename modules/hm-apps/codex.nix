/*
  Package: codex
  Description: Lightweight coding agent that runs in your terminal.
  Homepage: https://github.com/openai/codex
  Documentation: https://github.com/openai/codex/tree/main/docs
  Repository: https://github.com/openai/codex

  Summary:
    * Provides an interactive TUI that orchestrates code edits, tests, and tooling via OpenAI Codex with sandboxed execution and approvals.
    * Supports non-interactive automation, session resume, Model Context Protocol servers, and configurable instructions through `config.toml` and `AGENTS.md`.

  Options:
    --cd <path>: Set the working directory Codex should operate in before executing tasks.
    --profile <name>: Select a saved profile configuration for the current session.
    --approval-policy <mode>: Override the approval policy (for example `never`, `always`, `manual`).
    --sandbox-mode <mode>: Adjust the sandbox level for commands launched by Codex.

  Example Usage:
    * `codex "Write unit tests for src/date.ts"` — Ask Codex to draft and run new tests in the current repo.
    * `codex exec "explain utils.py"` — Produce a non-interactive explanation suitable for piping to other tools.
    * `codex resume --last` — Continue collaborating in the most recent workspace without starting from scratch.
*/

_: {
  flake.homeManagerModules.apps.codex =
    {
      osConfig,
      pkgs,
      config,
      lib,
      ...
    }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "codex" "extended" "enable" ] false osConfig;

      # Use upstream nixpkgs codex package
      baseCodexPkg = pkgs.codex;
      codexPkg =
        if lib.versionAtLeast (lib.getVersion baseCodexPkg) "0.2.0" then
          baseCodexPkg
        else
          # Upstream reports version 0.0.0 even on modern builds; wrap with a
          # synthetic name so Home Manager writes TOML config instead of the
          # legacy YAML path.
          pkgs.symlinkJoin {
            name = "codex-0.2.0-toml";
            paths = [ baseCodexPkg ];
            meta = baseCodexPkg.meta or { };
          };
      mcp = import ../../lib/mcp-servers.nix {
        inherit lib pkgs config;
      };

      codexMcpServers = mcp.selectWithoutType {
        sequential-thinking = true;
        memory = true;
        time = true;
        cfdocs = true;
        cfbindings = false;
        cfbuilds = false;
        cfobservability = false;
        cfradar = false;
        cfcontainers = false; # conflicts w/ builtin review command
        cfbrowser = true;
        cfgraphql = false;
        deepwiki = true;
        context7 = true;
      };
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.codex = {
          enable = true;
          package = codexPkg;
          settings = {
            show_raw_agent_reasoning = true;
            experimental_use_exec_command_tool = false;
            sandbox_mode = "danger-full-access";
            model = "gpt-5-codex";
            approval_policy = "never";
            profile = "gpt-5-codex";
            shell_environment_policy = {
              "inherit" = "all";
              ignore_default_excludes = true;
              exclude = [
                "AWS_*"
                "AZURE_*"
              ];
            };
            tui = {
              notifications = true;
            };
            tools = {
              web_search = true;
            };
            mcp_servers = codexMcpServers;
            profiles = {
              gpt-5-codex = {
                model = "gpt-5-codex";
                approval_policy = "never";
                model_supports_reasoning_summaries = true;
                model_reasoning_effort = "high";
                model_reasoning_summary = "detailed";
                model_verbosity = "medium";
              };
            };
          };
          custom-instructions = "";
        };

        home.packages = [ codexPkg ];
        home.sessionVariables = {
          CODEX_HOME = lib.mkDefault "${config.xdg.configHome}/codex";
          CODEX_DISABLE_UPDATE_CHECK = "1";
        };
      };
    };
}
