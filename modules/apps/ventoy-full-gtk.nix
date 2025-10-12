/*
  Package: ventoy-full-gtk
  Description: GTK GUI utility for creating multi-boot USB drives with Ventoy.
  Homepage: https://www.ventoy.net/
  Documentation: https://www.ventoy.net/en/doc_start.html
  Repository: https://github.com/ventoy/Ventoy

  Summary:
    * Provides the GTK frontend for Ventoy, making it easy to install or update Ventoy on USB drives.
    * Supports booting ISO/WIM/IMG/VHD(x)/EFI files directly without extraction.

  Example Usage:
    * `sudo ventoygui` - Launch the Ventoy GUI to select a USB drive and install Ventoy.
*/

{
  flake.nixosModules.apps."ventoy-full-gtk" =
    { pkgs, lib, ... }:
    let
      ventoyPkg = pkgs.ventoy-full-gtk;
    in
    {
      environment.systemPackages = [ ventoyPkg ];

      nixpkgs.config.permittedInsecurePackages = lib.mkAfter [ ventoyPkg.name ];
    };
}
