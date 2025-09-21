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
          lxsessionCommand = lib.getExe' pkgs.lxsession "lxsession";
          lockCommand = lib.attrByPath [ "gui" "i3" "lockCommand" ] null config;
        in
        {
          services = lib.mkMerge [
            {
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
            (lib.optionalAttrs (lockCommand != null) {
              screen-locker = {
                enable = true;
                lockCmd = lockCommand;
                inactiveInterval = 39;
                xautolock = {
                  enable = true;
                  detectSleep = true;
                };
                xss-lock.enable = false;
              };
            })
          ];

          systemd.user.services = lib.mkMerge [
            {
              autotiling-rs = {
                Unit = {
                  Description = "Autotiling for i3";
                  After = [ "graphical-session.target" ];
                  PartOf = [ "graphical-session.target" ];
                };
                Install.WantedBy = [ "graphical-session.target" ];
                Service = {
                  ExecStart = "${lib.getExe pkgs.autotiling-rs} --replace";
                  Restart = "on-failure";
                };
              };

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
            }
            (lib.optionalAttrs (lockCommand != null) {
              "i3lock-handler" = {
                Unit = {
                  Description = "Lock screen for suspend events";
                  Documentation = [ "man:i3lock(1)" ];
                  After = [ "graphical-session.target" ];
                  Before = [
                    "lock.target"
                    "sleep.target"
                  ];
                  PartOf = [
                    "lock.target"
                    "sleep.target"
                  ];
                  OnSuccess = [ "unlock.target" ];
                };
                Install = {
                  WantedBy = [
                    "lock.target"
                    "sleep.target"
                  ];
                };
                Service = {
                  Type = "simple";
                  ExecStart = "${lockCommand} --nofork";
                  Restart = "on-failure";
                  RestartSec = 0;
                };
              };
            })
          ];
        }
      );
    };
}
