/*
  Home App: virt-manager
  Description: Desktop client and viewer helpers for libvirt-managed virtual machines.
  Homepage: https://virt-manager.org/

  Summary:
    * Installs virt-manager and virt-viewer inside the user's profile for GUI access.
    * Aligns Home Manager package installation with the system-level libvirt tooling.
*/

_: {
  flake.homeManagerModules.apps."virt-manager" =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "virt-manager" "extended" "enable" ] false osConfig;
    in
    {
      # Package installed by NixOS module; HM provides user-level config if needed
      config = lib.mkIf nixosEnabled {
        # virt-manager doesn't have HM programs module - config managed by app itself
      };
    };
}
