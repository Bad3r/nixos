# Shell library for X11 primary monitor detection (RUNTIME)
# This is meant to be SOURCED by bash scripts, not executed directly
#
# Provides: query_primary_monitor function
# Exports: SCRATCHPAD_MONITOR_WIDTH, SCRATCHPAD_MONITOR_HEIGHT,
#          SCRATCHPAD_MONITOR_X, SCRATCHPAD_MONITOR_Y
#
# Usage:
#   . "${monitor-query}"
#   query_primary_monitor
#   echo "Monitor: ${SCRATCHPAD_MONITOR_WIDTH}x${SCRATCHPAD_MONITOR_HEIGHT}"
{ writeText }:

writeText "monitor-query" /* bash */ ''
  # monitor-query.sh: Query primary monitor via xrandr (X11)
  # Exports: SCRATCHPAD_MONITOR_WIDTH, SCRATCHPAD_MONITOR_HEIGHT,
  #          SCRATCHPAD_MONITOR_X, SCRATCHPAD_MONITOR_Y

  query_primary_monitor() {
    local monitor_info

    # Parse: "1920x1080+0+0" from xrandr output for primary monitor
    monitor_info=$(xrandr --query | while read -r line; do
      if [[ $line =~ \ connected\ primary\ ([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+) ]]; then
        echo "''${BASH_REMATCH[1]} ''${BASH_REMATCH[2]} ''${BASH_REMATCH[3]} ''${BASH_REMATCH[4]}"
        break
      fi
    done)

    if [[ -z "$monitor_info" ]]; then
      # Fallback: try first connected monitor if no primary
      monitor_info=$(xrandr --query | while read -r line; do
        if [[ $line =~ \ connected\ ([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+) ]]; then
          echo "''${BASH_REMATCH[1]} ''${BASH_REMATCH[2]} ''${BASH_REMATCH[3]} ''${BASH_REMATCH[4]}"
          break
        fi
      done)
    fi

    if [[ -z "$monitor_info" ]]; then
      echo "Error: Could not detect primary monitor" >&2
      return 1
    fi

    # Parse the space-separated values
    read -r SCRATCHPAD_MONITOR_WIDTH SCRATCHPAD_MONITOR_HEIGHT \
            SCRATCHPAD_MONITOR_X SCRATCHPAD_MONITOR_Y <<< "$monitor_info"

    # Export for use by caller
    export SCRATCHPAD_MONITOR_WIDTH
    export SCRATCHPAD_MONITOR_HEIGHT
    export SCRATCHPAD_MONITOR_X
    export SCRATCHPAD_MONITOR_Y
  }
''
