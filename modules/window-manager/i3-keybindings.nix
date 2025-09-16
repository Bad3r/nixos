{
  # Home Manager i3 keybindings for common actions
  flake.homeManagerModules.gui =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      # Resolve the configured modifier (e.g., "Mod4").
      mod = config.xsession.windowManager.i3.config.modifier;
      stylixAvailable = config ? stylix && config.stylix ? targets && config.stylix.targets ? i3;
      stylixExportedBarConfig =
        if stylixAvailable then config.stylix.targets.i3.exportedBarConfig else { };
      stylixFontName =
        if stylixAvailable && config.stylix.fonts ? sansSerif then
          config.stylix.fonts.sansSerif.name
        else
          null;
      stylixFontSize =
        if stylixAvailable && config.stylix.fonts ? sizes then config.stylix.fonts.sizes.desktop else null;
      stylixBarOptions =
        (lib.optionalAttrs (stylixExportedBarConfig ? colors) {
          inherit (stylixExportedBarConfig) colors;
        })
        // (lib.optionalAttrs (stylixFontName != null && stylixFontSize != null) {
          fonts = {
            names = [ stylixFontName ];
            size = stylixFontSize * 1.0;
          };
        });
    in
    lib.mkMerge [
      {
        xsession = {
          enable = true;
          windowManager.i3 = {
            enable = true;
            config = {
              # Use Super as the i3 modifier. Home Manager expands this to e.g. "Mod4".
              modifier = lib.mkDefault "Mod4";

              # Launch kitty and rofi without embedding store paths in the config.
              terminal = lib.getExe pkgs.kitty;
              menu = "${lib.getExe pkgs.rofi} -modi drun -show drun";

              # Keybindings requested (use resolved modifier, not "$mod").
              keybindings = {
                # super + Enter = new default terminal window (kitty)
                "${mod}+Return" = "exec ${lib.getExe pkgs.kitty}";

                # control + shift + q = close window
                # i3 expects the modifier name "Control" (not "Ctrl")
                "Control+Shift+q" = "kill";

                # super + d = run rofi (application launcher)
                "${mod}+d" = "exec ${lib.getExe pkgs.rofi} -modi drun -show drun";
              };

              # Recreate the status bar configuration while letting Stylix provide colors/fonts.
              bars = [
                (
                  {
                    mode = "dock";
                    hiddenState = "hide";
                    position = "bottom";
                    statusCommand = lib.getExe pkgs.i3status;
                    trayOutput = "primary";
                  }
                  // stylixBarOptions
                )
              ];
            };
          };
        };
      }
    ];
}
