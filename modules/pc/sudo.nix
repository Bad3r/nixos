{ config, ... }:
{
  flake.modules.nixos.pc =
    { pkgs, ... }:
    {
      security.sudo-rs = {
        enable = true; # replace sudo with memory-safe sudo-rs
        wheelNeedsPassword = true;
        # Make interactive password prompt wait indefinitely and extend cached auth duration
        extraConfig = ''
          Defaults passwd_timeout=0
          Defaults timestamp_timeout=10
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
      users.users.${config.flake.meta.owner.username}.extraGroups = [ "wheel" ];
    };
}
