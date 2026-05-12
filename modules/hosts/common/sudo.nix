{
  config,
  lib,
  metaOwner,
  ...
}:
let
  s76Share = config.flake.lib.nixos.hosts.system76.shareCommon;
  tpShare = config.flake.lib.nixos.hosts.tpnix.shareCommon;
  body =
    { pkgs, ... }:
    {
      security.sudo-rs = {
        enable = true;
        wheelNeedsPassword = true;
        extraConfig = ''
          Defaults passwd_timeout=0
          Defaults timestamp_timeout=10
          Defaults pwfeedback
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

      users.users.${metaOwner.username}.extraGroups = [ "wheel" ];
    };
in
{
  configurations.nixos.system76.module = lib.mkIf s76Share body;
  configurations.nixos.tpnix.module = lib.mkIf tpShare body;
}
