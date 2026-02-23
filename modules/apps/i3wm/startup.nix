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
      stickyKeyToggles = [
        {
          channel = "accessibility";
          property = "/StickyKeys";
        }
        {
          channel = "accessibility";
          property = "/StickyKeys/LatchToLock";
        }
        {
          channel = "accessibility";
          property = "/StickyKeys/TwoKeysDisable";
        }
        {
          channel = "accessibility";
          property = "/SlowKeys";
        }
        {
          channel = "accessibility";
          property = "/BounceKeys";
        }
        {
          channel = "accessibility";
          property = "/MouseKeys";
        }
        {
          channel = "xfce4-session";
          property = "/general/StartAssistiveTechnologies";
        }
      ];
      mkSetFalseCommand = toggle: {
        command =
          "${xfconfQuery} -c ${lib.escapeShellArg toggle.channel} -p ${lib.escapeShellArg toggle.property} -s false"
          + " || ${xfconfQuery} -c ${lib.escapeShellArg toggle.channel} -p ${lib.escapeShellArg toggle.property} -n -t bool -s false";
        always = true;
        notification = false;
      };
    in
    {
      config.xsession.windowManager.i3.config.startup = lib.mkAfter (
        (map mkSetFalseCommand stickyKeyToggles)
        ++ [
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
        ]
      );
    };
}
