/*
  Package: pavucontrol
  Description: GTK PulseAudio/PipeWire volume control utility.
*/

{
  flake.nixosModules.apps.pavucontrol =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.pavucontrol ];
    };
}
