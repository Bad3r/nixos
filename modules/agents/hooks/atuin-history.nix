# Records every shell command Claude Code and Codex run in atuin history,
# authored by the agent, with its exit code. Antigravity's hook payloads are
# not a format atuin parses; its controlled bash (antigravity-cli/_shell.nix)
# records its commands instead.
{ lib, ... }:
let
  hook =
    harness: event: client: matcher:
    let
      name = "atuin-history-${harness}-${lib.toLower event}";
    in
    lib.nameValuePair name {
      inherit name event;
      timeout = 10;
      package =
        pkgs:
        pkgs.writeShellApplication {
          name = "agent-atuin-history-${harness}";
          text = ''
            exec ${lib.getExe pkgs.atuin} hook ${harness}
          '';
        };
      ${client}.matcher = matcher;
    };
in
{
  flake.lib.agents._internal.hooks.raw = lib.listToAttrs [
    (hook "claude-code" "PreToolUse" "claude" "Bash")
    (hook "claude-code" "PostToolUse" "claude" "Bash")
    (hook "claude-code" "PostToolUseFailure" "claude" "Bash")
    (hook "codex" "PreToolUse" "codex" "^Bash$")
    (hook "codex" "PostToolUse" "codex" "^Bash$")
  ];
}
