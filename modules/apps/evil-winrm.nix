/*
  Package: evil-winrm
  Description: WinRM shell for penetration testing.
  Homepage: https://github.com/Hackplayers/evil-winrm
  Documentation: https://github.com/Hackplayers/evil-winrm#readme
  Repository: https://github.com/Hackplayers/evil-winrm

  Summary:
    * Opens an interactive PowerShell session over WinRM on Windows hosts.
    * Transfers files, loads scripts and binaries, and supports password, NTLM hash, Kerberos, and certificate authentication.

  Options:
    -i IP: Set the target host.
    -u USERNAME: Set the username.
    -p PASSWORD: Set the password.
    -H HASH: Authenticate with an NTLM hash.
    -S: Connect over SSL.
    -r REALM: Authenticate with Kerberos for the realm.
    -s SCRIPTS_PATH: Load PowerShell scripts from a local directory.
*/
_:
let
  EvilWinrmModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."evil-winrm".extended;
    in
    {
      options.programs."evil-winrm".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable evil-winrm.";
        };

        package = lib.mkPackageOption pkgs "evil-winrm" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.evil-winrm = EvilWinrmModule;
}
