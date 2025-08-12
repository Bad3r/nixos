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