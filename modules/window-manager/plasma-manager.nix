{ inputs, ... }:
{
  flake.modules.homeManager.pc = {
    imports = [ inputs.plasma-manager.homeManagerModules.plasma-manager ];

    programs.plasma = {
      enable = true;

      # Configure workspace behavior
      workspace = {
        clickItemTo = "select";
        lookAndFeel = "org.kde.breezedark.desktop";
        cursor.theme = "Breeze_Snow";
        iconTheme = "breeze-dark";
      };

      # Configure panels and widgets
      panels = [
        {
          location = "bottom";
          widgets = [
            {
              name = "org.kde.plasma.kickoff";
              config = {
                General.icon = "nix-snowflake";
              };
            }
            "org.kde.plasma.pager"
            "org.kde.plasma.taskmanager"
            "org.kde.plasma.marginsseparator"
            "org.kde.plasma.systemtray"
            "org.kde.plasma.digitalclock"
            "org.kde.plasma.showdesktop"
          ];
        }
      ];

      # Configure shortcuts
      shortcuts = {
        "kwin"."Switch to Desktop 1" = "Meta+1";
        "kwin"."Switch to Desktop 2" = "Meta+2";
        "kwin"."Switch to Desktop 3" = "Meta+3";
        "kwin"."Switch to Desktop 4" = "Meta+4";
        "kwin"."Window to Desktop 1" = "Meta+Shift+1";
        "kwin"."Window to Desktop 2" = "Meta+Shift+2";
        "kwin"."Window to Desktop 3" = "Meta+Shift+3";
        "kwin"."Window to Desktop 4" = "Meta+Shift+4";
      };

      # Configure window rules
      window-rules = [
        {
          description = "Firefox Picture-in-Picture";
          match = {
            window-class = {
              value = "firefox";
              type = "substring";
            };
            title = {
              value = "Picture-in-Picture";
              type = "substring";
            };
          };
          apply = {
            above = {
              value = true;
              apply = "force";
            };
            noborder = {
              value = true;
              apply = "force";
            };
          };
        }
      ];

      # Configure power management
      powerdevil = {
        AC = {
          powerButtonAction = "lockScreen";
          autoSuspend.action = "nothing";
          whenSleepingEnter = "standbyThenHibernate";
        };
        battery = {
          powerButtonAction = "sleep";
          autoSuspend = {
            action = "sleep";
            idleTimeout = 900;
          };
        };
        lowBattery = {
          whenLaptopLidClosed = "hibernate";
        };
      };

      # Configure desktop effects
      kwin = {
        effects = {
          dimAdminMode.enable = true;
          slide.enable = true;
          cube.enable = false;
          wobblyWindows.enable = false;
        };
        cornerBarrier = false;
        virtualDesktops = {
          number = 4;
          rows = 1;
        };
      };

      # Configure hotkeys for common applications
      hotkeys.commands = {
        "launch-terminal" = {
          name = "Launch Terminal";
          key = "Meta+Return";
          command = "konsole";
        };
        "launch-browser" = {
          name = "Launch Browser";
          key = "Meta+B";
          command = "firefox";
        };
      };
    };
  };
}
