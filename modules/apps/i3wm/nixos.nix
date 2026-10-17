# i3 NixOS module
# Enables X11 with i3 window manager and provides core system packages
let
  i3SessionModule =
    { pkgs, lib, ... }:
    {
      options.gui.i3 = {
        powerProfiles.allowSelection = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether the i3 power-profile launcher may switch away from the enforced host profile.";
        };

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
        };

        # Provide core tools referenced by the i3 session.
        environment.systemPackages = with pkgs; [
          arandr
          dunst
          hsetroot
          i3lock-color
          i3status-rust
          maim
          # picom is installed by modules/apps/picom.nix under
          # programs.picom.extended, which the app baseline turns on. Listing
          # it here as well installed a second, stock derivation that shadowed
          # an overridden package on PATH and survived turning the app off.
          rofi
          xclip
        ];
      };
    };
in
{
  flake.nixosModules.i3 = i3SessionModule;
}
