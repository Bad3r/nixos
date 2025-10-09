/*
  Home App: virt-manager
  Description: Desktop client and viewer helpers for libvirt-managed virtual machines.
  Homepage: https://virt-manager.org/

  Summary:
    * Installs virt-manager and virt-viewer inside the user's profile for GUI access.
    * Aligns Home Manager package installation with the system-level libvirt tooling.
*/

{
  flake.homeManagerModules.apps."virt-manager" =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        virt-manager
        virt-viewer
      ];
    };
}
