# Shell library for window geometry calculations
# This is meant to be SOURCED by bash scripts, not executed directly
# Dependencies: xrandr (must be in PATH when sourced)
#
# Usage in a package:
#   let
#     windowUtils = import ../../lib/shell/window-utils.nix { inherit (pkgs) writeText; };
#   in
#   writeShellApplication {
#     text = ''
#       . "${windowUtils}"
#       calculate_window_geometry
#       echo "Width: $TARGET_WIDTH"
#     '';
#   }
{ writeText }:

writeText "window-utils-lib" /* bash */ ''
  # window_utils.sh: Calculate window position and size for i3 scratchpads
  # Exports: TARGET_WIDTH, TARGET_HEIGHT, TARGET_X, TARGET_Y

  # Layout constants
  TOPBAR_HEIGHT=29
  TOP_GAP=6
  BOTTOM_GAP=6
  OUTER_GAP=4

  calculate_window_geometry() {
    # Parse monitor info in single xrandr call using bash parameter expansion
    # Format: WIDTHxHEIGHT+OFFSET_X+OFFSET_Y (e.g., 2560x1440+0+0)
    local monitor_info
    monitor_info=$(xrandr --query | while read -r line; do
      [[ $line =~ \ connected\ primary\ ([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+) ]] && \
        echo "''${BASH_REMATCH[1]} ''${BASH_REMATCH[2]} ''${BASH_REMATCH[3]} ''${BASH_REMATCH[4]}" && break
    done)

    if [[ -z $monitor_info ]]; then
      echo "Error: No primary monitor detected!" >&2
      return 1
    fi

    local screen_width screen_height screen_offset_x screen_offset_y
    read -r screen_width screen_height screen_offset_x screen_offset_y <<< "$monitor_info"

    # Determine width divisor: ultrawide (>=2:1) uses 1/3, standard uses 1/2
    # Integer comparison: width >= height*2 means aspect ratio >= 2.0
    local target_width
    if (( screen_width >= screen_height * 2 )); then
      target_width=$(( screen_width / 3 - OUTER_GAP ))
    else
      target_width=$(( screen_width / 2 - OUTER_GAP ))
    fi

    # All arithmetic done with bash builtins - no external processes
    export TARGET_WIDTH=$target_width
    export TARGET_HEIGHT=$(( screen_height - TOPBAR_HEIGHT - TOP_GAP - BOTTOM_GAP ))
    export TARGET_X=$(( screen_offset_x + screen_width - target_width ))
    export TARGET_Y=$(( screen_offset_y + TOPBAR_HEIGHT + TOP_GAP ))
  }
''
