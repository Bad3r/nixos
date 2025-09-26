/*
  Package: ai-tools
  Description: Bundle of terminal-first AI agents (Claude Code, Codex CLI, GitHub MCP Server) for assisted coding workflows.
  Homepage: https://anthropic.com/claude
  Documentation: https://docs.anthropic.com/en/docs/claude-code/overview
  Repository: https://github.com/anthropics/claude-code

  Summary:
    * Ships Anthropics' Claude Code CLI, OpenAI's Codex CLI, and GitHub's MCP server to enable AI pair-programming, reviews, and repository automation from the shell.
    * Provides ready-to-run binaries so you can authenticate with each provider and integrate them into editors, MCP-compliant tools, or terminal sessions.

  Options:
    claude: Launch Claude Code's conversational agent for repository-aware coding assistance.
    codex: Invoke OpenAI Codex CLI for code suggestions, issue triage, and review flows.
    github-mcp-server: Start the GitHub MCP server to expose repository operations to compliant AI clients.

  Example Usage:
    * `claude worktree --task "add pagination to invoices"` — Delegate a code change to Claude Code from the current repository.
    * `codex review --pr 42` — Ask Codex CLI to generate a natural-language code review for pull request #42.
    * `github-mcp-server stdio --read-only --toolsets code,issues` — Run the MCP server for read-only repository analysis tools.
*/

{
  flake.nixosModules.apps."ai-tools" =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        claude-code
        codex
        github-mcp-server
      ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        claude-code
        codex
        github-mcp-server
      ];
    };
}
