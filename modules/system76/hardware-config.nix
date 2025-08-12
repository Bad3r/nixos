# Module: system76/hardware-config.nix
# Purpose: Hardware Config configuration
# Namespace: flake.modules.configurations
# Pattern: Host configuration - System-specific settings and hardware

# Hardware-specific configuration for System76
{ config, ... }:
{
  configurations.nixos.system76.module = { pkgs, lib, ... }: {
    # Platform configuration (required)
    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
    
    # System76 hardware support
    hardware.system76.enableAll = true;
    
    # Enable Bluetooth
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
      settings = {
        General = {
          Experimental = true;
          KernelExperimental = true;
        };
      };
    };
    
    # Enable scanner support
    hardware.sane = {
      enable = true;
      extraBackends = with pkgs; [
        sane-airscan
        hplipWithPlugin
      ];
    };
    
    # Enable NTFS support
    boot.supportedFilesystems = [ "ntfs" ];
    
    # Enable touchpad support
    services.libinput = {
      enable = true;
      touchpad = {
        tapping = true;
        middleEmulation = true;
        naturalScrolling = true;
      };
    };
  };
}