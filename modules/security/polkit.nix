{
  flake.nixosModules.base = {
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
}
