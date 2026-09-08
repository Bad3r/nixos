{ lib, ... }:
{
  configurations.nixos.tpnix.module = {
    home-manager.sharedModules = lib.mkAfter [
      (
        {
          osConfig,
          pkgs,
          lib,
          ...
        }:
        let
          polkitEnabled = lib.attrByPath [ "security" "polkit" "enable" ] false osConfig;
          polkitAgentCommand = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
        in
        {
          config = lib.mkIf polkitEnabled {
            home.packages = [ pkgs.polkit_gnome ];

            systemd.user.services.polkit-gnome-authentication-agent-1 = {
              Unit = {
                Description = "Polkit authentication agent";
                After = [ "graphical-session.target" ];
                PartOf = [ "graphical-session.target" ];
              };
              Install = {
                WantedBy = [ "graphical-session.target" ];
              };
              Service = {
                ExecStart = polkitAgentCommand;
                Restart = "on-failure";
                RestartSec = 3;
              };
            };
          };
        }
      )
    ];
  };
}
