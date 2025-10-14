/*
  Package: vulkan-tools
  Description: Diagnostic utilities for Vulkan drivers (e.g., `vulkaninfo`, `vkcube`).
*/

{
  flake.nixosModules.apps."vulkan-tools" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."vulkan-tools" ];
    };
}
