/*
  Package: ssh-to-age
  Description: Convert ssh private keys in ed25519 format to age keys.
  Homepage: https://github.com/Mic92/ssh-to-age
  Documentation: https://github.com/Mic92/ssh-to-age
  Repository: https://github.com/Mic92/ssh-to-age

  Summary:
    * Converts Ed25519 SSH keys into age identities or recipients.
    * Supports stdin/stdout workflows for piping key material through other tools.

  Options:
    -i: Read SSH key material from a file or stdin.
    -o: Write the converted key to a file or stdout.
    -private-key: Convert a private key instead of emitting a public recipient.
*/
_:
let
  SshToAgeModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.ssh-to-age.extended;
    in
    {
      options.programs.ssh-to-age.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable ssh-to-age.";
        };

        package = lib.mkPackageOption pkgs "ssh-to-age" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.ssh-to-age = SshToAgeModule;
}
