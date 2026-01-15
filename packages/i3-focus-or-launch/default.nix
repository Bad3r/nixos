{
  lib,
  writeShellApplication,
  i3,
  jq,
}:

writeShellApplication {
  name = "i3-focus-or-launch";

  meta = {
    description = "Focus existing window by class or launch new instance";
    longDescription = ''
      Generic i3 utility that focuses an existing window matching a class pattern,
      or launches a new instance if no matching window exists.

      Usage:
        i3-focus-or-launch <class-pattern> <launch-command>

      Example:
        i3-focus-or-launch firefox 'firefox'
        i3-focus-or-launch 'google-chrome' 'google-chrome-stable'
    '';
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "i3-focus-or-launch";
  };

  runtimeInputs = [
    i3
    jq
  ];

  text = /* bash */ ''
    if [ "$#" -ne 2 ]; then
      echo "Usage: i3-focus-or-launch <class-pattern> <launch-command>" >&2
      exit 1
    fi

    CLASS_PATTERN="$1"
    LAUNCH_CMD="$2"

    # Check if any window with the class exists in i3 tree
    if i3-msg -t get_tree | jq -e --arg pattern "$CLASS_PATTERN" \
      '[.. | objects | select(.window_properties?.class? // "" | test($pattern; "i"))] | length > 0' \
      > /dev/null 2>&1; then
      i3-msg "[class=\"(?i)$CLASS_PATTERN\"] focus" > /dev/null
    else
      exec sh -c "$LAUNCH_CMD"
    fi
  '';
}
