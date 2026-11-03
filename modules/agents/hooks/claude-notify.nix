# Claude Code notifications as desktop toasts with the mascot icon; the
# built-in channel is off (preferredNotifChannel in claude-code/_settings.nix).
_: {
  flake.lib.agents._internal.hooks.raw.claude-notify = {
    name = "claude-notify";
    event = "Notification";
    timeout = 10;
    package =
      pkgs:
      let
        # Prints shell assignments for summary and body.
        filter = pkgs.writeText "claude-notify.jq" ''
          def esc: gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
          def clip($n): if length > $n then .[:$n - 1] + "…" else . end;
          def text: if type == "string" then . else "" end;

          if type != "object" then error("payload is not an object") else . end
          | ((.cwd | text) | rtrimstr("/") | split("/") | last // "") as $dir
          | ([.message, .title, .notification_type] | map(text) | map(select(test("\\S"))) | first // "Notification") as $msg
          | {
              summary: ("Claude Code" + (if $dir == "" then "" else " · " + $dir end)),
              body: ($msg | split("\n") | map(select(test("\\S"))) | .[:3] | join("\n") | clip(200))
            }
          | @sh "summary=\(.summary | esc) body=\(.body | esc)"
        '';
      in
      pkgs.writeShellApplication {
        name = "claude-notify";
        runtimeInputs = [
          pkgs.jq
          pkgs.libnotify
        ];
        text = ''
          summary="Claude Code"
          body=Notification
          if fields=$(jq -r -f ${filter} 2>/dev/null); then
            eval "$fields"
          fi
          exec notify-send --app-name="Claude Code" --icon=${./claude-notify-clawd.svg} -- "$summary" "$body"
        '';
      };

    claude = { };
  };
}
