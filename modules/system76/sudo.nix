{ config, ... }:
let
  owner = config.flake.lib.meta.owner.username;
in
{
  configurations.nixos.system76.module =
    { pkgs, ... }:
    {
      security.sudo-rs = {
        enable = true;
        wheelNeedsPassword = true;
        extraConfig = ''
          Defaults passwd_timeout=0
          Defaults timestamp_timeout=10
          Defaults env_keep += "SSH_AUTH_SOCK"
        '';
        extraRules = [
          {
            commands = [
              {
                command = "${pkgs.systemd}/bin/systemctl suspend";
                options = [ "NOPASSWD" ];
              }
              {
                command = "${pkgs.systemd}/bin/reboot";
                options = [ "NOPASSWD" ];
              }
              {
                command = "${pkgs.systemd}/bin/poweroff";
                options = [ "NOPASSWD" ];
              }
            ];
            groups = [ "wheel" ];
          }
        ];
      };

      users.users.${owner}.extraGroups = [ "wheel" ];
    };
}
