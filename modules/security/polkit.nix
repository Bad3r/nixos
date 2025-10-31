let
  module =
    { config, lib, ... }:
    let
      cfg = config.security.polkit.wheelPowerManagement;
    in
    {
      options.security.polkit.wheelPowerManagement = {
        enable = lib.mkEnableOption "password-less power management for wheel group members";
      };

      config = lib.mkIf cfg.enable {
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
      };
    };
in
{
  flake.nixosModules.base = module;
}
