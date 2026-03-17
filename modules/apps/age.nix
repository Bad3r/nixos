/*
  Package: age
  Description: Modern encryption tool with small explicit keys.
  Homepage: https://age-encryption.org/
  Documentation: https://age-encryption.org/
  Repository: https://github.com/FiloSottile/age

  Summary:
    * Encrypts files to explicit recipients using compact X25519-based age keys.
    * Supports password-based encryption, armored output, and key generation for automation or backups.

  Options:
    -d: Decrypt age-encrypted input to stdout or the selected output path.
    -o: Write ciphertext or plaintext to a specific output file.
    -r: Encrypt to the given recipient public key.
    -a: Emit ASCII-armored output instead of binary ciphertext.
*/
_:
let
  AgeModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.age.extended;
    in
    {
      options.programs.age.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable age.";
        };

        package = lib.mkPackageOption pkgs "age" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.age = AgeModule;
}
