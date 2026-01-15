{
  lib,
  writeShellApplication,
  i3,
  coreutils,
  jq,
}:

writeShellApplication {
  name = "i3-scratchpad-show-or-create";

  meta = {
    description = "Show existing i3 scratchpad or create new one with given command";
    longDescription = ''
      Generic i3 scratchpad manager that shows an existing scratchpad window
      by mark, or creates a new one if it doesn't exist.

      Usage:
        i3-scratchpad-show-or-create <i3_mark> <launch_cmd>

      Example:
        i3-scratchpad-show-or-create scratch-emacs 'emacsclient -c -a emacs'
        i3-scratchpad-show-or-create scratch-term 'kitty'

      The script:
      1. Checks if a window with the given mark exists
      2. If yes, shows the scratchpad
      3. If no, launches the command, waits for the window, marks it, and moves to scratchpad
    '';
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "i3-scratchpad-show-or-create";
  };

  runtimeInputs = [
    i3
    coreutils
    jq
  ];

  text = /* bash */ ''
    set -euo pipefail

    if [ "$#" -ne 2 ]; then
      echo "Usage: $0 <i3_mark> <launch_cmd>" >&2
      echo "Example: $0 'scratch-emacs' 'emacsclient -c -a emacs'" >&2
      exit 1
    fi

    I3_MARK="$1"
    LAUNCH_CMD="$2"

    scratchpad_exists() {
      i3-msg -t get_marks \
        | jq -e --arg mark "''${I3_MARK}" 'index($mark) != null' \
        >/dev/null
    }

    scratchpad_show() {
      if scratchpad_exists; then
        i3-msg "[con_mark=\"''${I3_MARK}\"] scratchpad show" >/dev/null
        return 0
      fi
      return 1
    }

    if scratchpad_show; then
      exit 0
    fi

    eval "''${LAUNCH_CMD}" &

    set +e
    WINDOW_ID="$(
      timeout 30 i3-msg -t subscribe '[ "window" ]' \
        | jq --unbuffered -r 'select(.change == "new") | .container.id' \
        | head -n1
    )"
    status=$?
    set -e

    if [ "''${status}" -ne 0 ] || [ -z "''${WINDOW_ID}" ]; then
      echo "Failed to detect new window for mark ''${I3_MARK}" >&2
      exit 1
    fi

    i3-msg "[con_id=''${WINDOW_ID}] mark \"''${I3_MARK}\", move scratchpad" >/dev/null
    scratchpad_show >/dev/null
  '';
}
