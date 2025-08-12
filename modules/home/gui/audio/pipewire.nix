# Note: System-level PipeWire config is in pc/pipewire.nix

{ lib, ... }:
{
  flake.modules.homeManager.gui = { pkgs, ... }: {
    home.packages = with pkgs; lib.mkDefault [
      pwvucontrol   # PipeWire volume control GUI
      qpwgraph      # PipeWire graph editor
      helvum        # GTK patchbay for PipeWire
    ];
  };
}
