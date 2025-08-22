{ config, ... }:
{
  configurations.nixos.tec.module = {
    # User vx configuration (shared with system76)
    # The actual user settings come from modules/meta/owner.nix
    # and the workstation namespace
    users.users.vx = {
      extraGroups = [
        "networkmanager"
        "wheel"
      ];
    };
  };
}
