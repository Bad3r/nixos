/*
  Single source of truth for the Claude Code environment variables that were
  otherwise hand-duplicated across the binary postFixup, settings.json, the
  Home Manager session variables, and the launch wrapper. Each consumer pulls
  exactly the subset it needs:

    * binary    baked into the Nix binary via wrapProgram (postFixup in
                modules/apps/claude-code.nix) so a bare `claude` that bypasses
                the ~/.local/bin wrapper still gets the privacy/update disables.
    * settings  ~/.claude/settings.json `env`, read by Claude at runtime
                regardless of launch path (binary disables + bash knobs).
    * all       full shell environment exported by the wrapper and the Home
                Manager session variables.

  Keeping the layers as one expression makes the belt-and-suspenders coverage
  explicit and removes the drift risk between sites.
*/
let
  # Privacy/telemetry/update disables baked into the binary.
  binary = {
    DISABLE_AUTOUPDATER = "1";
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
    DISABLE_NON_ESSENTIAL_MODEL_CALLS = "1";
    DISABLE_TELEMETRY = "1";
    DISABLE_INSTALLATION_CHECKS = "1";
  };

  # Bash tool knobs Claude also reads from settings.json `env`.
  bashRuntime = {
    CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR = "1";
    BASH_DEFAULT_TIMEOUT_MS = "240000";
    BASH_MAX_TIMEOUT_MS = "4800000";
  };

  # Shell-level vars not needed in settings.json.
  shellOnly = {
    CLAUDE_CODE_ENABLE_TELEMETRY = "0";
    DISABLE_ERROR_REPORTING = "1";
    BASH_MAX_OUTPUT_LENGTH = "1024";
    CLAUDE_CODE_DISABLE_TERMINAL_TITLE = "0";
    CLAUDE_CODE_IDE_SKIP_AUTO_INSTALL = "1";
    DISABLE_BUG_COMMAND = "1";
    USE_BUILTIN_RIPGREP = "0";
  };

  # Optional knobs left unset by default (enable by adding to a group above):
  #   ANTHROPIC_MODEL, MAX_THINKING_TOKENS = "32768",
  #   CLAUDE_CODE_MAX_OUTPUT_TOKENS, MAX_MCP_OUTPUT_TOKENS = "32000"
in
{
  inherit binary;
  settings = binary // bashRuntime;
  all = binary // bashRuntime // shellOnly;
}
