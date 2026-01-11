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

  Example Usage:
    * `codex "Write unit tests for src/date.ts"` — Ask Codex to draft and run new tests in the current repo.
    * `codex --model o3 "refactor auth module"` — Use a specific model for the task.
*/
_:
let
  CodexModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.codex.extended;
    in
    {
      options.programs.codex.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable codex.";
        };

        package = lib.mkPackageOption pkgs "codex" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.codex = CodexModule;
}
