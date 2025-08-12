# Module: pc/sudo.nix
# Purpose: Sudo and privilege escalation configuration
# Namespace: flake.modules.nixos.pc
# Pattern: Personal computer configuration - Extends base for desktop systems

# modules/sudo.nix

{ config, ... }:
{
  flake.modules.nixos.pc = { pkgs, ... }: {
    security.sudo-rs = {
      enable = true; # replace sudo with memory-safe sudo-rs
      wheelNeedsPassword = true;
      extraRules = [{
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
      }];
    };
    users.users.${config.flake.meta.owner.username}.extraGroups = [ "wheel" ];
  };
}
