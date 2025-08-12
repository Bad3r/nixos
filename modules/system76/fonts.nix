# Module: system76/fonts.nix
# Purpose: System and user package configuration
# Namespace: flake.modules.configurations
# Pattern: Host configuration - System-specific settings and hardware

# Font configuration for System76
{ config, ... }:
{
  configurations.nixos.system76.module = { pkgs, lib, ... }: {
    fonts = {
      enableDefaultPackages = true;
      packages = with pkgs; [
        noto-fonts
        noto-fonts-cjk-sans
        noto-fonts-emoji
        liberation_ttf
        fira-code
        fira-code-symbols
        jetbrains-mono
        font-awesome
        nerd-fonts.jetbrains-mono
        nerd-fonts.fira-code
        ubuntu_font_family
      ];
      
      fontconfig = {
        defaultFonts = {
          serif = [ "Noto Serif" ];
          sansSerif = [ "Noto Sans" ];
          monospace = [ "JetBrains Mono" ];
          emoji = [ "Noto Color Emoji" ];
        };
      };
    };
  };
}