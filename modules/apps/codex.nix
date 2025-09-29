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
  perSystem =
    { pkgs, ... }:
    {
      packages.codex = pkgs.callPackage ../../packages/codex { };
    };

  flake.nixosModules.apps.codex =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      codexPkg = lib.attrByPath [ "flake" "packages" pkgs.system "codex" ] (pkgs.callPackage
        ../../packages/codex
        { }
      ) config;
    in
    {
      environment.systemPackages = [ codexPkg ];
      environment.sessionVariables.CODEX_DISABLE_UPDATE_CHECK = "1";
    };

}
