# i3 session services configuration
# Defines systemd user services and Home Manager services for the i3 session
{
  flake.homeManagerModules.apps.i3-config =
    {
      config,
      osConfig ? { },
      pkgs,
      lib,
      ...
    }:
    let
      i3Enabled = lib.attrByPath [ "xsession" "windowManager" "i3" "enable" ] false config;
      hostI3Cfg = lib.attrByPath [ "gui" "i3" ] { } osConfig;
      xfsettingsdEnabled = lib.attrByPath [ "integrations" "xfsettingsd" "enable" ] true hostI3Cfg;
      primeSyncEnabled = lib.attrByPath [ "gpu" "nvidia" "prime" "syncActive" ] false osConfig;
    in
    {
      config = lib.mkIf i3Enabled (
        let
          kittyCommand = lib.getExe pkgs.kitty;
          nemoCommand = lib.getExe' pkgs.nemo "nemo";
          xfsettingsdCommand = "${pkgs.xfce4-settings}/bin/xfsettingsd";
          stylixColors = config.lib.stylix.colors.withHashtag or config.lib.stylix.colors;
          toLockColor = colorHex: lib.strings.toUpper (lib.removePrefix "#" colorHex + "FF");
          lockPalette = lib.mapAttrs (_: toLockColor) {
            background = stylixColors.base00;
            ring = stylixColors.base04;
            ringWrong = stylixColors.base08;
            ringVerify = stylixColors.base0B;
            line = stylixColors.base03;
            text = stylixColors.base05;
          };
          # i3lock-color forks once its window is mapped, which is the
          # readiness point Type=forking waits for.
          lockCommand = lib.escapeShellArgs [
            (lib.getExe pkgs.i3lock-color)
            "--color=${lockPalette.background}"
            "--inside-color=${lockPalette.background}"
            "--ring-color=${lockPalette.ring}"
            "--insidewrong-color=${lockPalette.background}"
            "--ringwrong-color=${lockPalette.ringWrong}"
            "--insidever-color=${lockPalette.background}"
            "--ringver-color=${lockPalette.ringVerify}"
            "--line-color=${lockPalette.line}"
            "--keyhl-color=${lockPalette.ringVerify}"
            "--bshl-color=${lockPalette.ringWrong}"
            "--time-color=${lockPalette.text}"
            "--date-color=${lockPalette.text}"
            "--layout-color=${lockPalette.text}"
            "--time-str=%%H:%%M:%%S"
            "--date-str=%%A, %%d %%B %%Y"
            "--radius=120"
            "--ring-width=10"
            "--clock"
          ];
          dimWarningScript = pkgs.writeShellApplication {
            name = "i3-dim-warning";
            runtimeInputs = [
              pkgs.brightnessctl
              pkgs.coreutils
            ];
            text = /* bash */ ''
              target=80

              # Hosts without a backlight (songbird) have nothing to dim.
              info=$(brightnessctl --class=backlight --machine-readable info 2>/dev/null) || exit 0
              IFS=, read -r _ _ _ current _ <<<"$info"
              if [ "''${current%\%}" -le "$target" ]; then
                exit 0
              fi

              brightnessctl --class=backlight --quiet --save set "$target%"
              (
                sleep 60
                brightnessctl --class=backlight --quiet --restore
              ) &
            '';
          };
          autotilingLauncher = pkgs.writeShellApplication {
            name = "autotiling-rs-launcher";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.i3
              pkgs.autotiling-rs
            ];
            text = /* bash */ ''
              set -euo pipefail

              socket=""
              for _ in $(seq 30); do
                socket="$(${lib.getExe pkgs.i3} --get-socketpath 2>/dev/null || true)"
                if [ -n "$socket" ] && [ -S "$socket" ]; then
                  break
                fi
                sleep 1
              done

              if [ -z "$socket" ] || [ ! -S "$socket" ]; then
                echo "autotiling-rs: failed to locate i3 socket" >&2
                exit 1
              fi

              exec env I3SOCK="$socket" ${lib.getExe pkgs.autotiling-rs}
            '';
          };
        in
        {
          services = {
            dunst = {
              enable = lib.mkDefault true;
            };
            # i3 does not composite, so without picom every GL/video present
            # reaches the scanout unsynchronised and tears. glx+vSync is the
            # backend pair NVIDIA needs; xrender (the module default) ignores
            # vSync entirely. PRIME-sync hosts disable vSync instead: their
            # NVIDIA screen has no CRTC, so picom's NVIDIA vblank wait never
            # returns once the panel blanks (tpnix froze hard on this), and
            # PRIME sync already keeps the sink scanout tear-free without it.
            # Follows the app registry rather than enabling unconditionally:
            # programs.picom.extended is the switch that installs picom, so a
            # host turning the app off would otherwise still run a
            # compositor, and one from home-manager's own pkgs.picom rather
            # than the package the app module installs.
            picom = {
              enable = lib.mkDefault (lib.attrByPath [ "programs" "picom" "extended" "enable" ] false osConfig);
              package = lib.mkDefault (
                lib.attrByPath [ "programs" "picom" "extended" "package" ] pkgs.picom osConfig
              );
              backend = lib.mkDefault "glx";
              vSync = lib.mkDefault (!primeSyncEnabled);
            };
            udiskie = {
              enable = lib.mkDefault true;
              tray = lib.mkDefault "always";
              settings = lib.mkDefault {
                program_options = {
                  file_manager = nemoCommand;
                  terminal = kittyCommand;
                };
              };
            };
            network-manager-applet.enable = lib.mkDefault true;
          };

          systemd.user.services = lib.mkMerge [
            {
              snixembed = {
                Unit = {
                  Description = "snixembed SNI-to-XEmbed tray bridge";
                  PartOf = [ "tray.target" ];
                  After = [ "graphical-session-pre.target" ];
                  Before = [ "tray.target" ];
                };
                Install.WantedBy = [ "tray.target" ];
                Service = {
                  Type = "dbus";
                  BusName = "org.kde.StatusNotifierWatcher";
                  ExecStart = lib.getExe pkgs.snixembed;
                  Restart = "on-failure";
                };
              };

              # Unit layout from the nixpkgs systemd-lock-handler docs; the
              # OnFailure release keeps lock.target startable after the
              # locker exhausts its restarts.
              i3lock = {
                Unit = {
                  Description = "i3lock-color screen locker";
                  Before = [ "lock.target" ];
                  PartOf = [ "lock.target" ];
                  OnSuccess = [ "unlock.target" ];
                  OnFailure = [ "unlock.target" ];
                };
                Install.WantedBy = [ "lock.target" ];
                Service = {
                  Type = "forking";
                  ExecStart = lockCommand;
                  Restart = "on-failure";
                  # A killed locker must relock, not count as a clean unlock.
                  RestartForceExitStatus = "SIGHUP SIGINT SIGTERM SIGPIPE";
                  RestartSec = 0;
                };
              };

              xautolock = {
                Unit = {
                  Description = "xautolock idle locker";
                  After = [ "graphical-session.target" ];
                  PartOf = [ "graphical-session.target" ];
                };
                Install.WantedBy = [ "graphical-session.target" ];
                Service = {
                  ExecStart = lib.concatStringsSep " " [
                    (lib.getExe pkgs.xautolock)
                    "-time 15"
                    "-locker '${pkgs.systemd}/bin/loginctl lock-session \${XDG_SESSION_ID}'"
                    "-detectsleep"
                    "-notify 60"
                    "-notifier ${lib.getExe dimWarningScript}"
                  ];
                  Restart = "always";
                };
              };

              autotiling-rs = {
                Unit = {
                  Description = "Autotiling for i3";
                  After = [ "graphical-session.target" ];
                  PartOf = [ "graphical-session.target" ];
                };
                Install.WantedBy = [ "graphical-session.target" ];
                Service = {
                  ExecStart = lib.getExe autotilingLauncher;
                  Restart = "on-failure";
                };
              };
            }
            (lib.optionalAttrs xfsettingsdEnabled {
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
            })
          ];
        }
      );
    };
}
