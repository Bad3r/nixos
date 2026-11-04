# Codex `notify` program: a readable toast per finished turn.
{
  pkgs,
  icon,
}:
let
  # Prints shell assignments for summary and body, or nothing to skip.
  filter = pkgs.writeText "codex-notify.jq" ''
    # The body takes markup; the summary is plain text.
    def esc: gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
    def clip($n): if length > $n then .[:$n - 1] + "…" else . end;
    def text: if type == "string" then . else "" end;

    if type != "object" then error("payload is not an object")
    elif .type == "agent-turn-complete" then
      # Thread-title requests from the TUI (codex-rs/tui/src/app/thread_title.rs:277, 0.166.0).
      if ((."input-messages"[0]? | text) | startswith("Generate a concise, single-line task title")) then empty
      else
        ((.cwd | text) | rtrimstr("/") | split("/") | last // "") as $dir
        | ((."last-assistant-message" | text) | split("\n") | map(select(test("\\S"))) | .[:3] | join("\n") | clip(200)) as $msg
        | {
            summary: ("Codex" + (if $dir == "" then "" else " · " + $dir end)),
            body: (if $msg == "" then "Turn complete" else $msg end)
          }
      end
    else {summary: "Codex", body: ("Event: " + (.type | text | if . == "" then "unknown" else . end))}
    end
    | @sh "summary=\(.summary) body=\(.body | esc)"
  '';
in
pkgs.writeShellApplication {
  name = "codex-notify";
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
