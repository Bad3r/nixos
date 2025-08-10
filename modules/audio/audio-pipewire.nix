# Module: audio-pipewire.nix
# Purpose: PC-specific audio configuration and tools
# Namespace: flake.modules.nixos.pc
# Dependencies: Assumes base PipeWire is configured in pc namespace
# Priority: Uses mkDefault for overrideable values

{ lib, ... }:
{
  flake.modules.nixos.pc = { pkgs, ... }: {
    # PC-specific audio packages
    environment.systemPackages = with pkgs; lib.mkDefault [
      # GUI audio tools
      pavucontrol
      qpwgraph
      helvum
      
      # Audio production (optional)
      ardour
      audacity
      
      # Media codecs
      gst_all_1.gstreamer
      gst_all_1.gst-plugins-base
      gst_all_1.gst-plugins-good
      gst_all_1.gst-plugins-bad
      gst_all_1.gst-plugins-ugly
    ];
    
    # Sound configuration is handled by PipeWire/ALSA
  };
}