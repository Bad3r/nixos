{
  lib,
  writeShellApplication,
  xorg,
  procps,
  libnotify,
  i3,
  coreutils,
  window-utils-lib,
  i3-scratchpad-show-or-create,
}:

writeShellApplication {
  name = "toggle-logseq";

  meta = {
    description = "Toggle Logseq as an i3 scratchpad with smart positioning";
    longDescription = ''
      Smart Logseq toggle script for i3 window manager.

      Features:
      - Shows/hides Logseq as a scratchpad window
      - Automatically calculates window size based on monitor resolution
      - Supports ultrawide (1/3 width) and standard (1/2 width) aspect ratios
      - Starts Logseq if not already running
      - Positions window on the right side of the primary monitor

      Usage:
        toggle-logseq

      Bind to a key in i3 config:
        bindsym $mod+l exec --no-startup-id toggle-logseq
    '';
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "toggle-logseq";
  };

  runtimeInputs = [
    xorg.xrandr
    procps
    libnotify
    i3
    coreutils # for sleep
    i3-scratchpad-show-or-create
  ];

  text = /* bash */ ''
    set -euo pipefail

    : "''${USR_LIB_DIR:="''${HOME}/.local/lib"}"
    window_utils_lib="${window-utils-lib}"

    if [ -f "''${USR_LIB_DIR}/window_utils" ]; then
      window_utils_lib="''${USR_LIB_DIR}/window_utils"
    fi

    # shellcheck source=/dev/null
    . "$window_utils_lib"

    calculate_window_geometry

    if ! pgrep -f logseq >/dev/null; then
      notify-send "Logseq" "Starting Logseq..."
      i3-scratchpad-show-or-create "Logseq" "logseq"
      sleep 5
    fi

    # shellcheck disable=SC2140
    i3-msg "[class=\"Logseq\"] scratchpad show, move position ''${TARGET_X}px ''${TARGET_Y}px, resize set ''${TARGET_WIDTH}px ''${TARGET_HEIGHT}px" >/dev/null
  '';
}
