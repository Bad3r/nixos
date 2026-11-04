# LightDM GTK greeter layout, appended to its GTK theme.
''
  #panel_window,
  #panel_window menubar {
    background: transparent;
    border: none;
    box-shadow: none;
  }

  #panel_window menuitem,
  #clock_menuitem {
    padding: 4px 10px;
  }

  #panel_window menuitem,
  #panel_window menuitem label,
  #clock_menuitem label {
    color: alpha(@window_fg_color, 0.7);
  }

  #login_window,
  #login_box,
  #content_frame,
  #buttonbox_frame {
    background: transparent;
    border: none;
    box-shadow: none;
  }

  #content_frame > border,
  #buttonbox_frame > border {
    border: none;
  }

  #user_combobox arrow {
    -gtk-icon-source: none;
    min-width: 0;
    min-height: 0;
  }

  #user_combobox button {
    padding-left: 20px;
    background: transparent;
    border: none;
    box-shadow: none;
    font-size: 15px;
    font-weight: 600;
  }

  #prompt_entry {
    min-height: 34px;
    padding: 0 16px;
    border-radius: 17px;
    -gtk-outline-radius: 17px;
    border: 1px solid alpha(@window_fg_color, 0.15);
    background-color: alpha(@window_fg_color, 0.07);
    box-shadow: none;
  }

  #prompt_entry:focus {
    border-color: @accent_bg_color;
    box-shadow: 0 0 0 2px alpha(@accent_bg_color, 0.35);
  }

  #cancel_button {
    min-height: 30px;
    padding: 0 16px;
    border-radius: 999px;
    -gtk-outline-radius: 999px;
  }

  /* Round arrow button; the label stays for screen readers. */
  #login_button {
    min-width: 34px;
    min-height: 34px;
    padding: 0;
    border-radius: 999px;
    -gtk-outline-radius: 999px;
    color: transparent;
    font-size: 1px;
    background: @accent_bg_color -gtk-icontheme("greeter-login") center / 16px no-repeat;
    border: none;
    box-shadow: none;
  }

  /* The greeter names the power window and its button after the action. */
  #restart_dialog,
  #shutdown_dialog {
    background-color: mix(@window_bg_color, @window_fg_color, 0.06);
    border-radius: 14px;
    border: 1px solid alpha(@window_fg_color, 0.1);
  }

  #restart_button,
  #shutdown_button {
    min-height: 30px;
    padding: 0 16px;
    border-radius: 999px;
    -gtk-outline-radius: 999px;
    background: @accent_bg_color;
    color: @accent_fg_color;
    border: none;
    box-shadow: none;
  }
''
