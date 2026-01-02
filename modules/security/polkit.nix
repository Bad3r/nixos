let
  module =
    { config, lib, ... }:
    let
      powerCfg = config.security.polkit.wheelPowerManagement;
      systemdCfg = config.security.polkit.wheelSystemdManagement;
    in
    {
      options.security.polkit = {
        wheelPowerManagement = {
          enable = lib.mkEnableOption "password-less power management for wheel group members";
        };

        wheelSystemdManagement = {
          enable = lib.mkEnableOption "password-less systemctl start/stop/restart for wheel group members";
        };
      };

      config = lib.mkMerge [
        (lib.mkIf powerCfg.enable {
          security.polkit = {
            enable = true;
            extraConfig = ''
              polkit.addRule(function(action, subject) {
                const powerActions = [
                  "org.freedesktop.login1.power-off",
                  "org.freedesktop.login1.power-off-multiple-sessions",
                  "org.freedesktop.login1.reboot",
                  "org.freedesktop.login1.reboot-multiple-sessions"
                ];

                if (subject.isInGroup("wheel") && powerActions.indexOf(action.id) !== -1) {
                  return polkit.Result.YES;
                }
              });
            '';
          };
        })

        (lib.mkIf systemdCfg.enable {
          security.polkit = {
            enable = true;
            extraConfig = ''
              polkit.addRule(function(action, subject) {
                if (action.id === "org.freedesktop.systemd1.manage-units" &&
                    subject.isInGroup("wheel")) {
                  return polkit.Result.YES;
                }
              });
            '';
          };
        })
      ];
    };
in
{
  flake.nixosModules.base = module;
}
