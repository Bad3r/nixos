/*
  Package: age-plugin-1p
  Description: Use SSH keys from 1Password with age.
  Homepage: nil
  Documentation: nil
  Repository: https://github.com/Enzime/age-plugin-1p

  Summary:
    * Lets age-compatible clients decrypt SSH recipients with matching SSH keys stored in 1Password.
    * Can print 1Password SSH public keys in OpenSSH authorized_keys format for use as age recipients.

  Options:
    --print-recipients: Print available 1Password SSH public keys in authorized_keys format.
    -j 1p: Ask age to discover and invoke the plugin during decryption.

  Notes:
    * Requires the 1Password CLI to be authenticated at runtime.
*/
_:
let
  AgePlugin1pModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."age-plugin-1p".extended;
    in
    {
      options.programs.age-plugin-1p.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable age-plugin-1p.";
        };

        package = lib.mkPackageOption pkgs "age-plugin-1p" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.age-plugin-1p = AgePlugin1pModule;
}
