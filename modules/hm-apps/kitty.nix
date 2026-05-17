/*
  Package: kitty
  Description: GPU-accelerated cross-platform terminal emulator with tiling, tabs, and remote control.
  Homepage: https://sw.kovidgoyal.net/kitty/
  Documentation: https://sw.kovidgoyal.net/kitty/conf/
  Repository: https://github.com/kovidgoyal/kitty

  Summary:
    * Renders text via OpenGL for high-performance terminal sessions with ligatures, Unicode support, and graphics protocol features.
    * Provides layout splits, session management, kitten subcommands, and remote control sockets for automation.

  Options:
    --config <file>: Launch kitty with an alternate configuration file.
    --session <file>: Restore a saved layout containing tabs and splits on startup.
    +kitten themes: Browse and apply color schemes interactively using the themes kitten.
    --single-instance: Reuse the existing kitty instance, creating new windows within it.
    +kitten ssh <host>: Initiate SSH sessions that inherit kitty's graphics protocol extensions.

  Example Usage:
    * `kitty` -- Start the terminal emulator with the default configuration.
    * `kitty --config ~/.config/kitty/presentation.conf` -- Apply an alternate profile on launch.
    * `kitty @ set-font-size 14` -- Adjust the font size of a running instance via remote control.
*/

_: {
  flake.homeManagerModules.apps.kitty =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "kitty" "extended" "enable" ] false osConfig;
      arabicRanges = lib.concatStringsSep "," [
        "U+0600-U+06FF"
        "U+0750-U+077F"
        "U+08A0-U+08FF"
        "U+FB50-U+FDFF"
        "U+FE70-U+FEFF"
      ];
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.kitty = {
          enable = true;
          # NixOS-managed zsh sources kitty integration in hosts/common/zsh.nix.
          shellIntegration.enableZshIntegration = false;
          # Ensure kitty is set as default terminal in user session
          settings = {
            # Font and glyph handling
            bold_font = "auto";
            italic_font = "auto";
            bold_italic_font = "auto";
            disable_ligatures = "never";
            font_features = "none";
            box_drawing_scale = "0.001, 1, 1.5, 2";
            # Nerd Font symbol mappings for icon glyphs
            # Format: comma-separated Unicode ranges followed by font name
            symbol_map =
              let
                nerdFontRanges = [
                  "U+E0A0-U+E0A3"
                  "U+E0B0-U+E0BF"
                  "U+E0C0-U+E0CF"
                  "U+E200-U+E2A9"
                  "U+E300-U+E3EB"
                  "U+E5FA-U+E62F"
                  "U+E700-U+E7C5"
                  "U+EA60-U+EC1E" # Codicons
                  "U+F000-U+F2E0"
                  "U+F300-U+F313"
                  "U+F400-U+F4A8"
                  "U+F500-U+FD46"
                ];
              in
              "${lib.concatStringsSep "," nerdFontRanges} Symbols Nerd Font Mono";
            # Cursor behaviour
            cursor_beam_thickness = "1.5";
            cursor_underline_thickness = "2.0";
            cursor_blink_interval = "-1";
            cursor_stop_blinking_after = "15.0";
            # Scrollback handling
            scrollback_lines = 20000;
            scrollback_pager = "less --chop-long-lines --RAW-CONTROL-CHARS +INPUT_LINE_NUMBER";
            scrollback_pager_history_size = 0;
            # Pointer and selection
            wheel_scroll_multiplier = "5.0";
            mouse_hide_wait = "3.0";
            url_style = "curly";
            open_url_with = "default";
            url_prefixes = "http https file ftp";
            copy_on_select = true;
            strip_trailing_spaces = "never";
            select_by_word_characters = "@-./_~?&=%+#";
            click_interval = "-1.0";
            focus_follows_mouse = false;
            pointer_shape_when_grabbed = "arrow";
            # Rendering cadence
            repaint_delay = 10;
            input_delay = 3;
            sync_to_monitor = true;
            enable_audio_bell = false;
            visual_bell_duration = "0.0";
            window_alert_on_bell = false;
            bell_on_tab = false;
            command_on_bell = "none";
            # Window sizing and chrome
            window_resize_step_cells = 2;
            window_resize_step_lines = 2;
            window_border_width = "0.0pt";
            draw_minimal_borders = true;
            window_margin_width = 0;
            single_window_margin_width = -1;
            window_padding_width = 12;
            placement_strategy = "center";
            inactive_text_alpha = "1.0";
            hide_window_decorations = true;
            resize_debounce_time = "0.1";
            resize_in_steps = false;
            # Tab bar configuration (colors handled by Stylix)
            tab_bar_edge = "bottom";
            tab_bar_margin_width = "0.0";
            tab_bar_style = "fade";
            tab_bar_min_tabs = 2;
            tab_fade = "0.25 0.5 0.75 1";
            tab_separator = "\" ┇\"";
            tab_title_template = "\"{title}\"";
            active_tab_title_template = "none";
            active_tab_font_style = "bold-italic";
            inactive_tab_font_style = "normal";
            tab_bar_background = "none";
            # Background opacity stays in sync with Stylix theme
            background_opacity = "1.000000";
            background_image = "none";
            background_image_layout = "tiled";
            background_image_linear = "no";
            dynamic_background_opacity = "yes";
            background_tint = "0.0";
            dim_opacity = "1.0";
            # Runtime helpers
            shell = ".";
            editor = "nvim";
            close_on_child_death = false;
            allow_remote_control = true;
            listen_on = "none";
            update_check_interval = "24.0";
            startup_session = "none";
            # `-ask` keeps kitty's permission prompt before honoring a
            # clipboard read OSC, so a remote process inside kitty can't
            # exfiltrate the clipboard silently. Plain `read-clipboard` /
            # `read-primary` would skip the prompt.
            clipboard_control = "write-clipboard write-primary read-clipboard-ask read-primary-ask";
            term = "xterm-kitty";
            kitty_mod = "ctrl+shift";
            # Grid first makes it the default layout; all built-in layouts remain reachable via next_layout
            enabled_layouts = lib.concatStringsSep "," [
              "grid"
              "splits"
              "tall"
              "fat"
              "horizontal"
              "vertical"
              "stack"
            ];
          };

          keybindings = {
            "kitty_mod+c" = "copy_to_clipboard";
            "kitty_mod+v" = "paste_from_clipboard";
            "kitty_mod+s" = "paste_from_selection";
            "shift+insert" = "paste_from_selection";
            "shift+enter" = "send_text all \\\\\\n";
            "kitty_mod+o" = "pass_selection_to_program";
            "kitty_mod+enter" = "new_window";
            "kitty_mod+equal" = "change_font_size all +2.0";
            "kitty_mod+minus" = "change_font_size all -2.0";
            # kitty_mod+backspace is free for future use
            "kitty_mod+0" = "change_font_size all 0";
            "kitty_mod+e" = "kitten hints";
            "kitty_mod+l" = "kitten hints --type line --program @";
            "kitty_mod+p>l" = "next_layout";
            "kitty_mod+a>m" = "set_background_opacity +0.1";
            "kitty_mod+a>l" = "set_background_opacity -0.1";
            "kitty_mod+a>1" = "set_background_opacity 1";
            "kitty_mod+a>d" = "set_background_opacity default";
            "kitty_mod+delete" = "clear_terminal reset active";
            # Layout shortcuts
            "ctrl+alt+g" = "goto_layout grid";
            "ctrl+alt+s" = "goto_layout splits";
            # Splits-layout spawning — goto_layout only switches the active layout, so
            # explicit hsplit/vsplit chords are needed to actually carve the active window.
            # kitty_mod+enter (new_window) still spawns on the layout's default axis.
            "kitty_mod+apostrophe" = "launch --location=hsplit --cwd=current";
            "kitty_mod+backslash" = "launch --location=vsplit --cwd=current";
            # Rotate uses kitty_mod+alt+r so the default kitty_mod+r (start_resizing_window) survives.
            "kitty_mod+alt+r" = "layout_action rotate";
            # Pane navigation — ctrl+alt avoids stealing shell word-movement (ctrl+arrow)
            # and the kitty_mod (ctrl+shift) chord space. Safe under i3, but ctrl+alt+arrow
            # is the desktop-switch chord on GNOME / KDE / XFCE / Cinnamon — revisit before
            # enabling this module on a host that runs a non-i3 desktop.
            "ctrl+alt+left" = "neighboring_window left";
            "ctrl+alt+right" = "neighboring_window right";
            "ctrl+alt+up" = "neighboring_window up";
            "ctrl+alt+down" = "neighboring_window down";
            # Pane resize — kitty_mod+alt+arrow keeps a materially distinct chord. Adding
            # ctrl on top of kitty_mod (ctrl+shift) would just deduplicate to kitty_mod+arrow
            # in the GLFW modifier bitmask, leaving no headroom for a future kitty_mod+arrow.
            "kitty_mod+alt+left" = "resize_window narrower";
            "kitty_mod+alt+right" = "resize_window wider";
            "kitty_mod+alt+up" = "resize_window taller";
            "kitty_mod+alt+down" = "resize_window shorter";
          };

          extraConfig = ''
            # Prefer an Arabic-capable font for Arabic codepoint ranges.
            symbol_map ${arabicRanges} Noto Sans Arabic UI
          '';
        };
      };
    };
}
