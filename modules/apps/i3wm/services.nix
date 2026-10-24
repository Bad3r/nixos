# i3 session services configuration
# Defines systemd user services and Home Manager services for the i3 session
{
  flake.homeManagerModules.apps.i3-config =
    {
      config,
      osConfig,
      pkgs,
      lib,
      ...
    }:
    let
      i3Enabled = config.xsession.windowManager.i3.enable;
      appRows = import ./_app-rows.nix { inherit lib osConfig pkgs; };
      primeSyncEnabled = osConfig.gpu.nvidia.prime.syncActive;
    in
    {
      config = lib.mkIf i3Enabled (
        let
          kittyCommand = lib.getExe (appRows.package "kitty");
          nemoCommand = lib.getExe' (appRows.package "nemo") "nemo";
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
          lockArgs = [
            (lib.getExe osConfig.programs.i3lock.package)
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
            "--time-str=%H:%M:%S"
            "--date-str=%A, %d %B %Y"
            "--radius=120"
            "--ring-width=10"
            "--clock"
          ];
          lockCommand = lib.replaceStrings [ "%" ] [ "%%" ] (lib.escapeShellArgs lockArgs);
          screensaverSeconds = 60;
          screensaverScript = pkgs.writeShellApplication {
            name = "i3-idle-screensaver";
            runtimeInputs = [
              pkgs.python3
              pkgs.xprintidle
            ];
            text = /* bash */ ''
              exec python3 ${./_idle-screensaver.py} ${toString screensaverSeconds} \
                ${lib.escapeShellArgs lockArgs} --nofork --no-verify
            '';
          };
          # Shadows the unthemed i3lock binary; the service execs it by store path.
          lockSessionCommand = pkgs.writeShellScriptBin "i3lock" ''
            exec ${pkgs.systemd}/bin/loginctl lock-session
          '';
          screensaverCondition = pkgs.writeShellScript "i3-idle-screensaver-condition" ''
            state=$(${pkgs.systemd}/bin/systemctl --user show i3lock.service --property=ActiveState --value) || exit 255
            case "$state" in
              inactive|failed) exit 0 ;;
              *) exit 1 ;;
            esac
          '';
          pinnedMode =
            if osConfig.gpu.nvidia.enable then
              builtins.match "([0-9]+x[0-9]+)_([0-9.]+)" osConfig.gpu.nvidia.metamode
            else
              null;
          # The NVIDIA driver discards every MetaMode when it reprobes while
          # the panel sleeps off the bus, so the panel returns with no mode.
          displayHotplugScript = pkgs.writeShellApplication {
            name = "display-hotplug";
            runtimeInputs = [
              pkgs.gnugrep
              pkgs.xrandr
            ];
            text = /* bash */ ''
              [ "$SRANDRD_EVENT" = connected ] || exit 0
              if xrandr --current | grep -Eq '^\S+ connected (primary )?[0-9]+x[0-9]+\+'; then
                exit 0
              fi
              echo "$SRANDRD_OUTPUT connected with no active output; enabling it" >&2
              ${
                if pinnedMode == null then
                  ''xrandr --output "$SRANDRD_OUTPUT" --auto''
                else
                  ''
                    xrandr --output "$SRANDRD_OUTPUT" --mode ${builtins.elemAt pinnedMode 0} --rate ${builtins.elemAt pinnedMode 1} ||
                      xrandr --output "$SRANDRD_OUTPUT" --auto''
              }
            '';
          };
        in
        {
          services = {
            dunst = {
              enable = lib.mkDefault (appRows.enabled "dunst");
              package = lib.mkDefault (appRows.package "dunst");
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
              enable = lib.mkDefault (appRows.enabled "picom");
              package = lib.mkDefault (appRows.package "picom");
              backend = lib.mkDefault "glx";
              vSync = lib.mkDefault (!primeSyncEnabled);
            };
            udiskie = {
              enable = lib.mkDefault (appRows.enabled "udiskie");
              package = lib.mkDefault (appRows.package "udiskie");
              tray = lib.mkDefault "always";
              settings = lib.mkDefault {
                program_options = {
                  file_manager = nemoCommand;
                  terminal = kittyCommand;
                };
              };
            };
            network-manager-applet = {
              enable = lib.mkDefault (appRows.enabled "networkmanagerapplet");
              package = lib.mkDefault (appRows.package "networkmanagerapplet");
            };
          };

          # Started by i3 itself (startup.nix), so units wanted by it run only
          # once the window manager is up.
          home.packages = lib.mkIf (appRows.enabled "i3lock-color") [ (lib.hiPrio lockSessionCommand) ];

          systemd.user.targets.i3-session.Unit = {
            Description = "i3 window manager session";
            BindsTo = [ "graphical-session.target" ];
            After = [ "graphical-session.target" ];
          };

          systemd.user.services = {
            snixembed = lib.mkIf (appRows.enabled "snixembed") {
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
                ExecStart = lib.getExe (appRows.package "snixembed");
                Restart = "on-failure";
              };
            };

            # Unit layout from the nixpkgs systemd-lock-handler docs; the
            # OnFailure release keeps lock.target startable after the
            # locker exhausts its restarts.
            i3lock = lib.mkIf (appRows.enabled "i3lock-color") {
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
                ExecStartPre = "${pkgs.systemd}/bin/systemctl --user stop i3-idle-screensaver.service";
                ExecStart = lockCommand;
                Restart = "on-failure";
                # A killed locker must relock, not count as a clean unlock.
                RestartForceExitStatus = "SIGHUP SIGINT SIGTERM SIGPIPE";
                RestartSec = 0;
              };
            };

            i3-idle-screensaver = {
              Unit = {
                Description = "Dismissible i3 idle screensaver";
                PartOf = [ "graphical-session.target" ];
              };
              Service = {
                ExecCondition = screensaverCondition;
                ExecStart = lib.getExe screensaverScript;
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
                  "-notify ${toString screensaverSeconds}"
                  "-notifier '${pkgs.systemd}/bin/systemctl --user start --no-block i3-idle-screensaver.service'"
                ];
                Restart = "always";
              };
            };

            display-hotplug = {
              Unit = {
                Description = "Re-enable a reconnected display left without a mode";
                After = [ "graphical-session.target" ];
                PartOf = [ "graphical-session.target" ];
              };
              Install.WantedBy = [ "graphical-session.target" ];
              Service = {
                ExecStart = "${lib.getExe pkgs.srandrd} -n ${lib.getExe displayHotplugScript}";
                Restart = "on-failure";
              };
            };
          }
          // lib.optionalAttrs (appRows.enabled "autotiling-rs") {
            autotiling-rs = {
              Unit = {
                Description = "Autotiling for i3";
                After = [ "i3-session.target" ];
                PartOf = [ "i3-session.target" ];
              };
              Install.WantedBy = [ "i3-session.target" ];
              Service = {
                ExecStart = lib.getExe (appRows.package "autotiling-rs");
                Restart = "on-failure";
              };
            };
          };
        }
      );
    };
}
