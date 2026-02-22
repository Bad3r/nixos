# i3 startup commands configuration
# Defines session startup commands and accessibility hardening
{
  flake.homeManagerModules.apps.i3-config =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      stylixColors = config.lib.stylix.colors.withHashtag or config.lib.stylix.colors;
      xfconfQuery = lib.getExe' pkgs.xfconf "xfconf-query";
    in
    {
      config.xsession.windowManager.i3.config.startup = lib.mkAfter [
        {
          command = ''
            set_bool() {
              ${xfconfQuery} -c "$1" -p "$2" -s false \
                || ${xfconfQuery} -c "$1" -p "$2" -n -t bool -s false
            }

            set_bool accessibility /StickyKeys
            set_bool accessibility /StickyKeys/LatchToLock
            set_bool accessibility /StickyKeys/TwoKeysDisable
            set_bool accessibility /SlowKeys
            set_bool accessibility /BounceKeys
            set_bool accessibility /MouseKeys
            set_bool xfce4-session /general/StartAssistiveTechnologies
          '';
          always = true;
          notification = false;
        }
        {
          command = "${lib.getExe' pkgs.hsetroot "hsetroot"} -solid '${stylixColors.base00}'";
          always = true;
          notification = false;
        }
        # DPMS: Keep screens on for 1 hour (3600s) before standby/suspend/off
        {
          command = "${pkgs.xset}/bin/xset dpms 3600 3600 3600";
          always = true;
          notification = false;
        }
        # Screen saver: Blank after 1 hour (3600s)
        {
          command = "${pkgs.xset}/bin/xset s 3600 3600";
          always = true;
          notification = false;
        }
      ];
    };
}
