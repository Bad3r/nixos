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
      primeSyncEnabled = lib.attrByPath [ "gpu" "nvidia" "prime" "syncActive" ] false osConfig;
      brightnessctlPackage = lib.attrByPath [
        "programs"
        "brightnessctl"
        "extended"
        "package"
      ] pkgs.brightnessctl osConfig;
    in
    {
      config = lib.mkIf i3Enabled (
        let
          kittyCommand = lib.getExe pkgs.kitty;
          nemoCommand = lib.getExe' pkgs.nemo "nemo";
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
              brightnessctlPackage
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

          # Started by i3 itself (startup.nix), so units wanted by it run only
          # once the window manager is up.
          systemd.user.targets.i3-session.Unit = {
            Description = "i3 window manager session";
            BindsTo = [ "graphical-session.target" ];
            After = [ "graphical-session.target" ];
          };

          systemd.user.services = {
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
                After = [ "i3-session.target" ];
                PartOf = [ "i3-session.target" ];
              };
              Install.WantedBy = [ "i3-session.target" ];
              Service = {
                ExecStart = lib.getExe pkgs.autotiling-rs;
                Restart = "on-failure";
              };
            };
          };
        }
      );
    };
}
