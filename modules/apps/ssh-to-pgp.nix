/*
  Package: ssh-to-pgp
  Description: Convert ssh private keys to PGP.
  Homepage: https://github.com/Mic92/ssh-to-pgp
  Documentation: https://github.com/Mic92/ssh-to-pgp
  Repository: https://github.com/Mic92/ssh-to-pgp

  Summary:
    * Converts SSH keys into OpenPGP key material for public or private key export.
    * Lets you set user ID metadata and choose armored or binary output.

  Options:
    -name: Set the name component for the generated OpenPGP user ID.
    -email: Set the email component for the generated OpenPGP user ID.
    -comment: Set the comment component for the generated OpenPGP user ID.
    -format: Choose binary or ASCII-armored OpenPGP encoding.
    -i: Read SSH key material from a file or stdin.
    -o: Write the converted key to a file or stdout.
    -private-key: Export a private key instead of a public key.
*/
_:
let
  SshToPgpModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.ssh-to-pgp.extended;
    in
    {
      options.programs.ssh-to-pgp.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable ssh-to-pgp.";
        };

        package = lib.mkPackageOption pkgs "ssh-to-pgp" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.ssh-to-pgp = SshToPgpModule;
}
