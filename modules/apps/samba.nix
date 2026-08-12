/*
  Package: samba
  Description: Standard Windows interoperability suite of programs for Linux and Unix.
  Homepage: https://www.samba.org/
  Documentation: https://www.samba.org/samba/docs/
  Repository: https://gitlab.com/samba-team/samba

  Summary:
    * Provides SMB/CIFS client access, NetBIOS name queries, and MS-RPC client utilities.
    * Includes `smbclient`, `nmblookup`, and `rpcclient` for Windows and Samba enumeration workflows.

  Options:
    smbclient //SERVER/SHARE: Access an SMB/CIFS share with an FTP-like client.
    nmblookup NAME: Query NetBIOS names and map them to IP addresses.
    rpcclient HOST: Execute client-side MS-RPC commands against a host.
    -U USERNAME: Set the SMB username and optionally prompt for its password.

  Notes:
    * The package exposes client binaries but no `samba` executable. Use `nix shell nixpkgs#samba -c smbclient --version` for ad-hoc checks.
*/
_:
let
  SambaModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.samba.extended;
    in
    {
      options.programs.samba.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable samba.";
        };

        package = lib.mkPackageOption pkgs "samba" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.samba = SambaModule;
}
