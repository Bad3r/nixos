# Scratchpad geometry configuration for i3/X11
# Provides options for scratchpad window positioning and a geometry calculator
# Uses pure bash arithmetic (no bc/awk) for performance
{
  flake.homeManagerModules.gui =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      cfg = config.gui.scratchpad;

      # Create the geometry calculator package with injected options
      scratchpadGeometryPackage = pkgs.writeShellApplication {
        name = "scratchpad-geometry";

        meta = {
          description = "Calculate scratchpad window geometry based on monitor and config";
          longDescription = ''
            Scratchpad geometry calculator for i3/X11.

            Detects primary monitor via xrandr and calculates optimal
            window dimensions based on configured offsets and ratios.

            Output format (eval-able):
              TARGET_WIDTH=<pixels>
              TARGET_HEIGHT=<pixels>
              TARGET_X=<pixels>
              TARGET_Y=<pixels>

            Usage:
              eval "$(scratchpad-geometry)"
              echo "Window size: ''${TARGET_WIDTH}x''${TARGET_HEIGHT}"
          '';
          license = lib.licenses.mit;
          platforms = lib.platforms.linux;
          mainProgram = "scratchpad-geometry";
        };

        runtimeInputs = [
          pkgs.xorg.xrandr
        ];

        text = /* bash */ ''
          set -euo pipefail

          # Source monitor detection library (from overlay: pkgs.monitor-query)
          # shellcheck source=/dev/null
          . "${pkgs.monitor-query}"

          # Nix-injected configuration (build-time constants)
          # All values are integers for pure bash arithmetic
          TOP_OFFSET=${toString cfg.topOffset}
          BOTTOM_OFFSET=${toString cfg.bottomOffset}
          SIDE_OFFSET=${toString cfg.sideOffset}
          WIDTH_PERCENT=${toString cfg.widthPercent}
          SCALE_PERCENT=${toString cfg.scale}
          POSITION="${cfg.position}"

          # Query primary monitor (sets SCRATCHPAD_MONITOR_* variables)
          query_primary_monitor

          # Calculate dimensions using pure bash arithmetic
          screen_width="$SCRATCHPAD_MONITOR_WIDTH"
          screen_height="$SCRATCHPAD_MONITOR_HEIGHT"
          screen_x="$SCRATCHPAD_MONITOR_X"
          screen_y="$SCRATCHPAD_MONITOR_Y"

          # Calculate dimensions with scale applied to content area, not offsets
          # Scale is applied to the window size, offsets remain screen-relative
          scaled_content_width=$(( screen_width * WIDTH_PERCENT / 100 * SCALE_PERCENT / 100 ))
          scaled_content_height=$(( (screen_height - TOP_OFFSET - BOTTOM_OFFSET) * SCALE_PERCENT / 100 ))

          # Subtract offsets AFTER scaling (offsets are screen-relative, not scaled)
          target_width=$(( scaled_content_width - SIDE_OFFSET ))
          target_height=$scaled_content_height

          # Calculate X position based on configured position
          case "$POSITION" in
            left)
              target_x=$(( screen_x + SIDE_OFFSET ))
              ;;
            center)
              target_x=$(( screen_x + (screen_width - target_width) / 2 ))
              ;;
            right|*)
              target_x=$(( screen_x + screen_width - target_width ))
              ;;
          esac

          target_y=$(( screen_y + TOP_OFFSET ))

          # Output in eval-able format
          echo "TARGET_WIDTH=$target_width"
          echo "TARGET_HEIGHT=$target_height"
          echo "TARGET_X=$target_x"
          echo "TARGET_Y=$target_y"
        '';
      };
    in
    {
      options.gui.scratchpad = {
        topOffset = lib.mkOption {
          type = lib.types.int;
          default = 35;
          description = ''
            Pixels from top of screen to top of scratchpad window.
            Typically: bar height + gap (e.g., 29 + 6 = 35).
          '';
          example = 40;
        };

        bottomOffset = lib.mkOption {
          type = lib.types.int;
          default = 6;
          description = "Pixels from bottom of screen to bottom of scratchpad window.";
          example = 10;
        };

        sideOffset = lib.mkOption {
          type = lib.types.int;
          default = 4;
          description = "Pixels from screen edge to scratchpad window.";
          example = 8;
        };

        widthPercent = lib.mkOption {
          type = lib.types.int;
          default = 50;
          description = ''
            Width as percentage of screen.
            50 = 50% of screen width (half screen).
          '';
          example = 40;
        };

        scale = lib.mkOption {
          type = lib.types.int;
          default = 100;
          description = ''
            Scale factor as percentage for final window dimensions.
            100 = no scaling (default).
            150 = 150% size (for HiDPI or preference).
            75 = 75% size (smaller window).
          '';
          example = 150;
        };

        position = lib.mkOption {
          type = lib.types.enum [
            "left"
            "center"
            "right"
          ];
          default = "right";
          description = "Horizontal position of scratchpad window on screen.";
          example = "center";
        };

        # Expose the geometry package for other modules to use
        geometryPackage = lib.mkOption {
          type = lib.types.package;
          default = scratchpadGeometryPackage;
          readOnly = true;
          description = ''
            The scratchpad-geometry package with configuration baked in.
            Use this in other packages or scripts.
          '';
        };

        geometryCommand = lib.mkOption {
          type = lib.types.str;
          default = lib.getExe scratchpadGeometryPackage;
          readOnly = true;
          description = ''
            Full path to the scratchpad-geometry executable.
            Usage: eval "$(''${config.gui.scratchpad.geometryCommand})"
          '';
        };
      };

      config = {
        # Add geometry calculator to user's packages
        home.packages = [ cfg.geometryPackage ];
      };
    };
}
