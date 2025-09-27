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
          dimWarningScript = pkgs.writeShellApplication {
            name = "i3-dim-warning";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.procps
              pkgs.gawk
              pkgs.xorg.xbacklight
            ];
            text = ''
              set -eu

              target=80
              cache_dir="''${XDG_CACHE_HOME:-$HOME/.cache}/i3lock"
              brightness_file="$cache_dir/brightness"

              current=$(xbacklight -get 2>/dev/null || printf "")
              if [ -z "$current" ]; then
                exit 0
              fi

              if ! awk "BEGIN {exit !($current > $target)}"; then
                exit 0
              fi

              mkdir -p "$cache_dir"
              printf '%s\n' "$current" > "$brightness_file"

              xbacklight -set "$target" >/dev/null 2>&1 || true

              restore_brightness() {
                if [ -f "$brightness_file" ]; then
                  target_restore=$(cat "$brightness_file")
                  xbacklight -set "$target_restore" >/dev/null 2>&1 || true
                  rm -f "$brightness_file"
                fi
              }

              (
                set +e
                set +u
                for _ in $(seq 60); do
                  sleep 1
                  if pgrep -x i3lock-color >/dev/null; then
                    exit 0
                  fi
                done

                if ! pgrep -x i3lock-color >/dev/null; then
                  restore_brightness
                fi
              ) &
            '';
          };
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
                  extraOptions = [
                    "-notify"
                    "60"
                    "-notifier"
                    (lib.getExe dimWarningScript)
                  ];
                };
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
                  ExecStart = lib.getExe pkgs.autotiling-rs;
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
              "xss-lock" = {
                Install.WantedBy = lib.mkForce [ ];
              };
            })
          ];
        }
      );
    };
}
