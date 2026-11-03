/*
  Package: i3wm
  Description: Tiling window manager.
  Homepage: https://i3wm.org
  Repository: https://github.com/i3/i3

  Summary:
    * Tiling window manager for X11, configured through a plain-text file.
    * Arranges windows in a tree of containers with split, stacked, and tabbed layouts.
*/
let
  i3SessionModule =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      options.gui.i3 = {
        # Display geometry hints consumed by the Home Manager i3 config via
        # osConfig (window-positioning math and the calendar dropdown offset).
        screenWidth = lib.mkOption {
          type = lib.types.int;
          default = 2560;
          description = "Primary screen width in pixels for i3 window-positioning math.";
          example = 1920;
        };

        screenHeight = lib.mkOption {
          type = lib.types.int;
          default = 1440;
          description = "Primary screen height in pixels for i3 window-positioning math.";
          example = 1080;
        };

        barHeight = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = null;
          description = "Rendered i3bar height in pixels. null lets the Home Manager i3 config derive it from fontSize and borderWidth.";
          example = 24;
        };
      };

      config = {
        # X11 + i3 window manager
        services = {
          xserver = {
            enable = lib.mkDefault true;
            windowManager.i3 = {
              enable = true;
              package = pkgs.i3;
              # Upstream adds dmenu and i3status; dmenu has its own app row and the bar runs i3status-rust.
              extraPackages = [ ];
            };
            displayManager.lightdm.enable = true;
          };

          displayManager.defaultSession = lib.mkDefault "none+i3";

          "systemd-lock-handler".enable = lib.mkDefault true;
        };

        # The i3 Home Manager config needs the packages these rows' gated overlays provide.
        programs = {
          "i3-focus-or-launch".extended.enable = lib.mkOverride 1050 true;
          "i3-scratchpad-show-or-create".extended.enable = lib.mkOverride 1050 true;
          "monitor-query".extended.enable = lib.mkOverride 1050 true;
          snixembed.extended.enable = lib.mkOverride 1050 true;
          # lock.target's only locker is the unit this row gates.
          "i3lock-color".extended.enable = lib.mkOverride 1050 true;
          # display-hotplug sets NVIDIA modes through nvidia-settings.
          "nvidia-settings".extended.enable = lib.mkIf config.gpu.nvidia.enable (lib.mkOverride 1050 true);
        };
      };
    };
in
{
  flake.nixosModules.i3 = i3SessionModule;
}
