/*
  Package: ventoy-full
  Description: CLI bundle for creating multi-boot USB drives with Ventoy (no GUI).
  Homepage: https://www.ventoy.net/
  Documentation: https://www.ventoy.net/en/doc_start.html
  Repository: https://github.com/ventoy/Ventoy

  Summary:
    * Installs the full Ventoy command-line toolchain with filesystem helpers (ext4, NTFS, XFS, LUKS).
    * Lets you initialise or update Ventoy on removable media without needing the upstream GTK/Qt frontends.

  Example Usage:
    * `sudo ventoy` - Launch the interactive CLI menu to select a target disk and install Ventoy.
    * `sudo ventoy -I /dev/sdX` - Install Ventoy to `/dev/sdX` in one shot.
    * `sudo ventoy -U /dev/sdX` - Update an existing Ventoy installation.
*/

{
  flake.nixosModules.apps."ventoy-full" =
    { pkgs, lib, ... }:
    let
      ventoyPkg = pkgs."ventoy-full";
    in
    {
      environment.systemPackages = [ ventoyPkg ];

      # Ventoy ships upstream binary blobs that nixpkgs flags insecure; allow it explicitly.
      nixpkgs.config.permittedInsecurePackages = lib.mkAfter [ ventoyPkg.name ];
    };
}
