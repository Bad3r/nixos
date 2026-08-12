/*
  Package: smbmap
  Description: SMB enumeration tool.
  Homepage: https://github.com/ShawnDEvans/smbmap
  Documentation: https://github.com/ShawnDEvans/smbmap#readme
  Repository: https://github.com/ShawnDEvans/smbmap

  Summary:
    * Enumerates SMB shares and permissions across hosts in a domain.
    * Supports recursive listing, file search, upload/download, and remote command execution.

  Options:
    -H HOST: Scan a single IP address or FQDN.
    -u USERNAME: Set the SMB username.
    -p PASSWORD: Set a password or NTLM hash.
    -r PATH: Recursively list directories and files.
    -x COMMAND: Execute a command on the target host.
    --signing: Check whether SMB signing is disabled, enabled, or required.
*/
_:
let
  SmbmapModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.smbmap.extended;
    in
    {
      options.programs.smbmap.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable smbmap.";
        };

        package = lib.mkPackageOption pkgs "smbmap" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.smbmap = SmbmapModule;
}
