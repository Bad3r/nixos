/*
  Package: netexec
  Description: Network service exploitation tool and maintained CrackMapExec fork.
  Homepage: https://github.com/Pennyw0rth/NetExec
  Documentation: https://www.netexec.wiki/
  Repository: https://github.com/Pennyw0rth/NetExec

  Summary:
    * Provides the `nxc` CLI for network service discovery and authenticated Active Directory enumeration.
    * Supports SMB, WinRM, MSSQL, LDAP, SSH, RDP, FTP, NFS, VNC, and WMI protocols.

  Options:
    smb: Enumerate and interact with SMB targets.
    ldap: Enumerate LDAP services and Active Directory objects.
    --shares: Enumerate available SMB shares.
    -u USERNAME: Supply a username or credential file.
    -p PASSWORD: Supply a password or credential file.

  Notes:
    * The nixpkgs package is named `netexec`, while its primary executable is `nxc`.
*/
_:
let
  NetexecModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.netexec.extended;
    in
    {
      options.programs.netexec.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable netexec.";
        };

        package = lib.mkPackageOption pkgs "netexec" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.netexec = NetexecModule;
}
