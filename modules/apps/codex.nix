/*
  Package: codex
  Description: OpenAI Codex CLI for GPT-powered coding assistance, reviews, and automations.
  Homepage: https://github.com/openai/openai-codex-cli
  Documentation: https://github.com/openai/openai-codex-cli
  Repository: https://github.com/openai/openai-codex-cli

  Summary:
    * Supplies a command-line interface to run Codex prompts against local repositories or ad-hoc code snippets.
    * Features structured commands for reviewing diffs, summarising issues, and generating patches via API calls.

  Options:
    codex login: Store OpenAI API credentials for subsequent invocations.
    codex review --pr <number>: Generate narrative feedback for a pull request.
    codex run --prompt <file>: Execute a custom prompt file with embedded instructions.

  Example Usage:
    * `codex login` — Configure authentication for the CLI.
    * `codex review --pr 42` — Produce a natural-language review summary for PR #42.
    * `codex apply --task "add tests for session manager"` — Request patch suggestions for the given task.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
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
          description = lib.mdDoc "Whether to enable codex.";
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
