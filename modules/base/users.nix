# Module: base/users.nix
# Purpose: Centralized user configuration for the system owner
# Namespace: flake.modules.nixos.base
# Pattern: Single source of truth for user account configuration

{ config, lib, ... }:
{
  flake.modules.nixos.base = { pkgs, ... }: {
    # Create the owner's user account
    users.users.${config.flake.meta.owner.username} = {
      isNormalUser = true;
      description = config.flake.meta.owner.name;
      initialPassword = "";  # Force password change on first login
      shell = pkgs.zsh;  # Default shell
      
      # Base groups that the user should be in
      extraGroups = [
        "wheel"           # Admin privileges
        "networkmanager"  # Network configuration
        "audio"           # Audio devices
        "video"           # Video devices
        "input"           # Input devices
        "dialout"         # Serial ports
        "render"          # GPU acceleration
      ];
      
      # SSH authorized keys for remote access
      openssh.authorizedKeys.keys = config.flake.meta.owner.sshKeys;
    };
    
    # Make the owner a trusted Nix user
    nix.settings.trusted-users = [ config.flake.meta.owner.username ];
    
    # Enable zsh since it's the default shell
    programs.zsh.enable = true;
  };
}