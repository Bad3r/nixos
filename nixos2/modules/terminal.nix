{ lib, ... }:
{
  flake.modules.homeManager = {
    base =
      { pkgs, ... }:
      {
        options.terminal = {
          path = lib.mkOption {
            type = lib.types.path;
            default = null;
          };
          withTitle = lib.mkOption {
            type = lib.types.functionTo lib.types.str;
            default = null;
          };
        };

        config.home.packages = with pkgs; [ ansifilter ];
      };
    gui =
      { config, pkgs, ... }:
      {
        terminal = {
          path = lib.getExe config.programs.ghostty.package;
          withTitle = cmd: "${config.terminal.path} --title ${cmd} --command ${cmd}";
        };

        programs.ghostty = {
          enable = true;
          shellIntegration.enable = true;
          enableZshIntegration = true;
          installBatSyntax = true;
          installVimSyntax = true;

          settings = {
            #theme = "nord";
            background-blur-radius = 20;
            #window-theme = "dark";
            window-theme = "system";
            background-opacity = 0.8;
            minimum-contrast = 1.1;
            title = "GhosTTY";
            window-save-state = "always";
            gtk-single-instance = true;
            gtk-titlebar = false;
            shell-integration-features = "cursor,sudo";
            cursor-blink = true;
            window-padding-x = "4,4";
            window-padding-y = "4,4";

            keybindings = [
              "global:ctrl+`=toggle_quick_terminal"
              "ctrl+shift+h=goto_split:left"
              "ctrl+shift+l=goto_split:right"
              "ctrl+shift+j=goto_split:down"
              "ctrl+shift+k=goto_split:up"
            ];
          };

        };

        inputs.stylix.targets.ghostty.enable = true;

        xserver.windowManager.i3.config = {
          terminal = config.terminal.path;
          keybindings = {
            "Mod4+Return" = null;
            "--no-repeat Mod4+Return" = "exec ${lib.getExe config.programs.ghostty.package}";
            "--no-repeat Mod4+Shift+Return" =
              "exec ${lib.getExe config.programs.ghostty.package} --working-directory `${lib.getExe pkgs.xcwd}`";
          };
        };
      };
  };
}
