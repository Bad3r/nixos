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
        filter = pkgs.writeText "claude-notify.jq" (
          builtins.readFile ../_notify.jq
          + ''
            if type != "object" then error("payload is not an object") else . end
            | ([.message, .title, .notification_type] | map(text) | map(select(test("\\S"))) | first // "Notification") as $msg
            | {summary: title("Claude Code"), body: ($msg | excerpt)}
            | fields
          ''
        );
      in
      pkgs.writeShellApplication {
        name = "claude-notify";
        passthru = { inherit filter; };
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
