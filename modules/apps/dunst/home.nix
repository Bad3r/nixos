/*
  Package: dunst
  Description: Lightweight and highly configurable notification daemon for X11/Wayland.
  Homepage: https://dunst-project.org/
  Documentation: https://dunst-project.org/documentation/

  Notes:
    * Stylix owns font, icon theme, text and accent colors (modules/stylix/stylix.nix); the toast
      surface and border match rofi's window. The i3 session enables the service
      (modules/apps/i3wm/services.nix).
*/

_: {
  flake.homeManagerModules.apps.dunst =
    {
      config,
      osConfig,
      lib,
      pkgs,
      ...
    }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "dunst" "extended" "enable" ] false osConfig;
      colors = config.lib.stylix.colors.withHashtag;
      # Frosted glass as in rofi: the sidebar color at 75% over picom's backdrop blur.
      toastBackground = "${colors.base01}bf";
      toastRadius = 8;
      toastBorder = colors.base02;
      i3Gap = config.xsession.windowManager.i3.config.gaps.inner;
      # dunst multiplies sizes by dpi / 96, and per_monitor_dpi takes dpi from the
      # monitor's EDID size: 1440 px over 340 mm is 107 dpi.
      dpiScale = 107 / 96.0;
      scale = px: builtins.floor (px * dpiScale + 0.5);
      unscale = px: builtins.floor (px / dpiScale + 0.5);
    in
    {
      config = lib.mkIf nixosEnabled {
        # picom blurs the toast stack and rounds it at dunst's drawn radius.
        services.picom.settings.corner-radius-rules = [
          "${toString (scale toastRadius)}:class_g = 'Dunst'"
        ];

        services.dunst.settings = {
          global = {
            follow = "mouse";

            # dunst 1.7 split the old `geometry = "280x50-10+44"` into these three. Its height
            # counted notifications, not pixels.
            width = 280;
            notification_limit = 50;
            # On the top-right corner of the tiled window area.
            offset = "(${toString (unscale i3Gap)}, ${toString (unscale (config.gui.i3.barHeight + i3Gap))})";

            padding = 14;
            horizontal_padding = 16;
            # One glass box for the whole stack.
            gap_size = 0;
            # A frame-colored hairline between toasts.
            separator_height = 1;
            separator_color = lib.mkForce "frame";
            line_height = 4;
            frame_width = 1;
            corner_radius = toastRadius;

            markup = "full";
            format = "<b>%s</b>\\n%b";
            show_indicators = false;
            # Icons by name from Stylix's icon theme and its parents; icon_path goes unread.
            enable_recursive_icon_lookup = true;
            icon_theme = config.services.dunst.iconTheme.name;
            # The theme lookup matches min_icon_size exactly; one size for every toast icon.
            min_icon_size = 32;
            max_icon_size = 32;

            sort = false;
            idle_threshold = 120;
            # The 1.13.2 default is `do_action, remove_current`.
            mouse_middle_click = "do_action, close_current";
            # The built-in default is /usr/bin/xdg-open, which NixOS does not have.
            browser = lib.getExe' pkgs.xdg-utils "xdg-open";
          };

          experimental.per_monitor_dpi = true;

          urgency_low = {
            timeout = 2;
            background = lib.mkForce toastBackground;
            frame_color = lib.mkForce toastBorder;
          };
          urgency_normal = {
            timeout = 3;
            background = lib.mkForce toastBackground;
            frame_color = lib.mkForce toastBorder;
          };
          urgency_critical = {
            background = lib.mkForce toastBackground;
            frame_color = lib.mkForce colors.base08;
          };
        };
      };
    };
}
