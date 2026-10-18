/*
  Package: dunst
  Description: Lightweight and highly configurable notification daemon for X11/Wayland.
  Homepage: https://dunst-project.org/
  Documentation: https://dunst-project.org/documentation/

  Notes:
    * Behavior and geometry only. Stylix owns colors, font and icon theme (modules/stylix/stylix.nix),
      and the i3 session enables the service (modules/apps/i3wm/services.nix).
*/

_: {
  flake.homeManagerModules.apps.dunst =
    {
      osConfig,
      lib,
      pkgs,
      ...
    }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "dunst" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        services.dunst.settings = {
          global = {
            follow = "mouse";

            # dunst 1.7 split the old `geometry = "280x50-10+44"` into these three. Its height
            # counted notifications, not pixels.
            width = 280;
            notification_limit = 50;
            offset = "(10, 44)";

            padding = 20;
            horizontal_padding = 20;
            separator_height = 4;
            line_height = 4;
            frame_width = 0;

            markup = "full";
            format = "%s\\n%b";
            show_indicators = false;
            min_icon_size = 0;
            max_icon_size = 48;

            sort = false;
            idle_threshold = 120;
            # The 1.13.2 default is `do_action, remove_current`.
            mouse_middle_click = "do_action, close_current";
            # The built-in default is /usr/bin/xdg-open, which NixOS does not have.
            browser = lib.getExe' pkgs.xdg-utils "xdg-open";
          };

          experimental.per_monitor_dpi = true;

          urgency_low.timeout = 3;
          urgency_normal.timeout = 5;
        };
      };
    };
}
