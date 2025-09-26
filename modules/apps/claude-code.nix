/*
  Package: claude-code
  Description: Anthropics' Claude Code CLI for repository-aware conversations and code generation.
  Homepage: https://docs.anthropic.com/en/docs/claude-code/overview
  Documentation: https://docs.anthropic.com/en/docs/claude-code/overview
  Repository: https://github.com/anthropics/claude-code

  Summary:
    * Provides a terminal client that connects to Claude for iterative coding, planning, and troubleshooting sessions.
    * Supports worktree context ingestion so Claude can read, diff, and suggest updates within git repositories.

  Options:
    claude-code login: Authenticate the CLI with an API key or OAuth flow.
    claude-code run <task>: Execute a scripted task definition against the current repository.
    claude-code worktree --task <prompt>: Start an interactive session using local git state.

  Example Usage:
    * `claude-code login` — Initiate authentication and store encrypted credentials locally.
    * `claude-code worktree --task "refactor telemetry collection"` — Ask Claude to propose git changes for a task.
    * `claude-code run ci-audit.yml` — Execute a saved automation recipe against the repo.
*/

{
  flake.nixosModules.apps."claude-code" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.claude-code ];
    };

}
