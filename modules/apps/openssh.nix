/*
  Package: openssh
  Description: Implementation of the SSH protocol.
  Homepage: https://www.openssh.com/
  Documentation: https://www.openssh.com/

  Summary:
    * Provides secure remote login, command execution, tunneling, and file-transfer clients.
    * Ships the `ssh`, `scp`, and `sftp` frontends used for encrypted administrative access.

  Options:
    -i: Select a specific identity file for authentication.
    -L [bind_address:]port:host:hostport: Create a local TCP forward.
    user@host: Connect to a remote SSH server using standard destination syntax.
*/
_:
let
  OpensshModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.openssh.extended;
    in
    {
      options.programs.openssh.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable openssh.";
        };

        package = lib.mkPackageOption pkgs "openssh" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.openssh = OpensshModule;
}
