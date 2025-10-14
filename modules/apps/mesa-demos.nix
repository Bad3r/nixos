/*
  Package: mesa-demos
  Description: OpenGL/Vulkan demonstration utilities for exercising graphics drivers.
*/

{
  flake.nixosModules.apps."mesa-demos" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."mesa-demos" ];
    };
}
