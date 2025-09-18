{
  flake.homeManagerModules.gui =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      i3Enabled = lib.attrByPath [ "xsession" "windowManager" "i3" "enable" ] false config;
    in
    {
      config = lib.mkIf i3Enabled (
        let
          kittyCommand = lib.getExe pkgs.kitty;
          dolphinCommand = lib.getExe' pkgs.kdePackages.dolphin "dolphin";
          xfsettingsdCommand = "${pkgs.xfce.xfce4-settings}/bin/xfsettingsd";
          xfce4PowerManagerCommand = lib.getExe' pkgs.xfce.xfce4-power-manager "xfce4-power-manager";
          lxsessionCommand = lib.getExe' pkgs.lxsession "lxsession";
          lockCommand = lib.attrByPath [ "gui" "i3" "lockCommand" ] null config;
        in
        {
          services = {
            dunst.enable = lib.mkDefault true;
            picom = {
              enable = lib.mkDefault true;
              settings = lib.mkDefault {
                backend = "glx";
              };
            };
            udiskie = {
              enable = lib.mkDefault true;
              tray = lib.mkDefault "always";
              settings = lib.mkDefault {
                program_options = {
                  file_manager = dolphinCommand;
                  terminal = kittyCommand;
                };
              };
            };
            network-manager-applet.enable = lib.mkDefault true;
          }
          // lib.optionalAttrs (lockCommand != null) {
            screen-locker = {
              enable = true;
              lockCmd = lockCommand;
              inactiveInterval = 39;
              xautolock = {
                enable = true;
                extraOptions = [
                  "-notify"
                  "60"
                  "-notifier"
                  "${pkgs.xorg.xset}/bin/xset dpms force off"
                ];
              };
            };
          };

          systemd.user.services = {
            lxsession = {
              Unit = {
                Description = "LXSession session manager";
                After = [ "graphical-session.target" ];
                PartOf = [ "graphical-session.target" ];
              };
              Install.WantedBy = [ "graphical-session.target" ];
              Service = {
                ExecStart = lxsessionCommand;
                Restart = "on-failure";
              };
            };

            xfsettingsd = {
              Unit = {
                Description = "Xfce settings daemon";
                After = [ "graphical-session.target" ];
                PartOf = [ "graphical-session.target" ];
              };
              Install.WantedBy = [ "graphical-session.target" ];
              Service = {
                ExecStart = xfsettingsdCommand;
                Restart = "on-failure";
              };
            };

            "xfce4-power-manager" = {
              Unit = {
                Description = "Xfce power manager";
                After = [
                  "graphical-session.target"
                  "tray.target"
                ];
                Requires = [ "tray.target" ];
                PartOf = [ "graphical-session.target" ];
              };
              Install.WantedBy = [ "graphical-session.target" ];
              Service = {
                ExecStart = xfce4PowerManagerCommand;
                Restart = "on-failure";
              };
            };
          };
          xsession.initExtra = ''
            ${pkgs.xorg.xset}/bin/xset s 60 60
            ${pkgs.xorg.xset}/bin/xset s blank
            ${pkgs.xorg.xset}/bin/xset +dpms
            ${pkgs.xorg.xset}/bin/xset dpms 0 0 120
          '';
        }
      );
    };
}
