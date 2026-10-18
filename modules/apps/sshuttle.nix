/*
  Package: sshuttle
  Description: Transparent proxy server that forwards connections over SSH.
  Homepage: https://github.com/sshuttle/sshuttle
  Documentation: https://sshuttle.readthedocs.io/
  Repository: https://github.com/sshuttle/sshuttle

  Summary:
    * Routes selected network traffic through an SSH connection.
    * Supports DNS tunneling.
*/
_:
let
  SshuttleModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.sshuttle.extended;
    in
    {
      options.programs.sshuttle.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable sshuttle.";
        };

        package = lib.mkPackageOption pkgs "sshuttle" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.sshuttle = SshuttleModule;
}
