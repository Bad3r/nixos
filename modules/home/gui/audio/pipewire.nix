# Module: pipewire.nix
# Purpose: User-level PipeWire GUI tools and utilities
# Namespace: flake.modules.homeManager.gui
# Dependencies: Assumes PipeWire is configured at system level (pc/pipewire.nix)
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
