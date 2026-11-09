# Herdr's agent-session hooks, run from the pinned Herdr source in place of the
# copies `herdr integration install` writes beside each harness's config. The
# scripts report the session to the enclosing Herdr pane and exit 0 elsewhere,
# including when python3 is missing, so the wrapper supplies it.
{ inputs, lib, ... }:
let
  hook =
    agent:
    {
      name = "herdr-${agent}-session";
      event = "SessionStart";
      timeout = 10;
      package =
        pkgs:
        let
          inherit (inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.herdr) src;
        in
        pkgs.writeShellApplication {
          name = "herdr-${agent}-session";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.python3
          ];
          text = ''
            exec ${pkgs.runtimeShell} ${src}/src/integration/assets/${agent}/herdr-agent-state.sh session
          '';
        };
    }
    // lib.optionalAttrs (agent == "claude") {
      # Herdr's SESSION_START_MATCHER (src/integration/claude_settings.rs).
      claude.matcher = "^(startup|resume|clear|compact|fork)$";
    }
    // lib.optionalAttrs (agent == "codex") { codex = { }; };
in
{
  flake.lib.agents._internal.hooks.raw = {
    herdr-claude-session = hook "claude";
    herdr-codex-session = hook "codex";
  };
}
