# i3 startup commands configuration
# Defines session startup commands
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
      stylixColors = config.lib.stylix.colors.withHashtag or config.lib.stylix.colors;
      appRows = import ./_app-rows.nix { inherit lib osConfig pkgs; };
    in
    {
      config.xsession.windowManager.i3.config.startup = lib.mkAfter [
        {
          command = "${pkgs.systemd}/bin/systemctl --user start i3-session.target";
          notification = false;
        }
        {
          command = "${lib.getExe' (appRows.package "hsetroot") "hsetroot"} -solid '${stylixColors.base00}'";
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
