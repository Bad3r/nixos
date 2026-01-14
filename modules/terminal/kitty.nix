{
  flake.homeManagerModules.gui =
    { lib, ... }:
    {
      programs.kitty = {
        enable = true;
        # Ensure kitty is set as default terminal in user session
        settings = {
          # Font and glyph handling
          bold_font = "auto";
          italic_font = "auto";
          bold_italic_font = "auto";
          adjust_line_height = "0";
          adjust_column_width = "0";
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
          open_url_modifiers = "kitty_mod";
          open_url_with = "default";
          url_prefixes = "http https file ftp";
          copy_on_select = true;
          strip_trailing_spaces = "never";
          rectangle_select_modifiers = "ctrl+alt";
          terminal_select_modifiers = "shift";
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
          resize_draw_strategy = "static";
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
          dynamic_background_opacity = "no";
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
          clipboard_control = "write-clipboard write-primary";
          term = "xterm-kitty";
          kitty_mod = "ctrl+shift";
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
          "kitty_mod+backspace" = "change_font_size all 0";
          "kitty_mod+e" = "kitten hints";
          "kitty_mod+a>m" = "set_background_opacity +0.1";
          "kitty_mod+a>l" = "set_background_opacity -0.1";
          "kitty_mod+a>1" = "set_background_opacity 1";
          "kitty_mod+a>d" = "set_background_opacity default";
          "kitty_mod+delete" = "clear_terminal reset active";
        };
      };
    };
}
