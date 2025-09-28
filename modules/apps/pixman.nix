/*
  Package: pixman
  Description: Low-level pixel manipulation library used by cairo and other renderers.
  Homepage: https://cairographics.org/
  Repository: https://gitlab.freedesktop.org/pixman/pixman

  Summary:
    * Supplies compositing and raster operations for 2D graphics stacks.
    * Provides the `pixman-1.pc` pkg-config file that native builds like node-canvas require.
*/

{
  flake.nixosModules.apps.pixman =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.pixman ];
    };

}
