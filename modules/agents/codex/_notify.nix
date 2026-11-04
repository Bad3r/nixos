# Codex `notify` program: a readable toast per finished turn.
{
  pkgs,
  icon,
}:
let
  # Thread-title requests from the TUI (codex-rs/tui/src/app/thread_title.rs).
  titlePrefix = "Generate a concise, single-line task title";
  # Prints shell assignments for summary and body, or nothing to skip.
  filter = pkgs.writeText "codex-notify.jq" (
    builtins.readFile ../_notify.jq
    + ''
      if type != "object" then error("payload is not an object")
      elif .type == "agent-turn-complete" then
        if ((."input-messages"[0]? | text) | startswith(${builtins.toJSON titlePrefix})) then empty
        else
          ((."last-assistant-message" | text) | excerpt) as $msg
          | {summary: title("Codex"), body: (if $msg == "" then "Turn complete" else $msg end)}
        end
      else {summary: "Codex", body: ("Event: " + (.type | text | if . == "" then "unknown" else . end))}
      end
      | fields
    ''
  );
in
pkgs.writeShellApplication {
  name = "codex-notify";
  passthru = { inherit filter titlePrefix; };
  runtimeInputs = [
    pkgs.jq
    pkgs.libnotify
  ];
  text = ''
    summary=Codex
    body=Notification
    if fields=$(jq -r -f ${filter} <<<"''${1-}" 2>/dev/null); then
      [ -n "$fields" ] || exit 0
      eval "$fields"
    fi
    exec notify-send --app-name=Codex --icon=${icon} -- "$summary" "$body"
  '';
}
