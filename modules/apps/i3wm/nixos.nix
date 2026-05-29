# i3 NixOS module
# Enables X11 with i3 window manager and provides core system packages
let
  i3SessionModule =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      cfg = config.gui.i3;
    in
    {
      options.gui.i3 = {
        integrations = {
          xfsettingsd.enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether the i3 session should run xfsettingsd and ship the related Xfce tooling.";
          };
        };

        powerProfiles.backend = lib.mkOption {
          type = lib.types.enum [
            "system76-power"
            "powerprofilesctl"
          ];
          default = "system76-power";
          description = "Power-profile backend exposed to shared i3 launcher scripts.";
        };

        powerProfiles.allowSelection = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether the i3 power-profile launcher may switch away from the enforced host profile.";
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

        # Auto-enable the i3 session's hard package dependencies so their
        # gated overlays in modules/custom-overlays/ register on this host.
        # Without this, modules/apps/i3wm/{config,scratchpad,services}.nix
        # would reference `pkgs.<helper>` attributes that never get added,
        # producing "attribute missing" eval errors. Uses `lib.mkDefault` so
        # a host can still disable a specific helper with a higher-priority
        # override (`= false` or `lib.mkForce false`).
        programs = {
          "i3-focus-or-launch".extended.enable = lib.mkDefault true;
          "i3-scratchpad-show-or-create".extended.enable = lib.mkDefault true;
          "monitor-query".extended.enable = lib.mkDefault true;
          snixembed.extended.enable = lib.mkDefault true;
        };

        # Provide core tools referenced by the i3 session.
        environment.systemPackages =
          with pkgs;
          [
            arandr
            autotiling-rs
            dunst
            hsetroot
            i3lock-color
            i3status-rust
            maim
            picom
            rofi
            xclip
            xbacklight
          ]
          ++ lib.optionals cfg.integrations.xfsettingsd.enable [
            xfce4-power-manager
            xfce4-settings
          ];
      };
    };
in
{
  flake.nixosModules.i3 = i3SessionModule;
}
