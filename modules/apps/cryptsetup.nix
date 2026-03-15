/*
  Package: cryptsetup
  Description: LUKS for dm-crypt.
  Homepage: https://gitlab.com/cryptsetup/cryptsetup/
  Documentation: https://gitlab.com/cryptsetup/cryptsetup/
  Repository: https://gitlab.com/cryptsetup/cryptsetup/

  Summary:
    * Manages LUKS and plain dm-crypt devices for encrypted volumes on Linux systems.
    * Supports formatting, opening, resizing, converting, and inspecting encrypted container metadata.

  Options:
    luksFormat: Initialize a block device or file as a new LUKS container.
    open: Map an encrypted device to a decrypted name under `/dev/mapper`.
    close: Tear down an existing decrypted mapping.
    luksDump: Inspect LUKS metadata, keyslots, and encryption parameters.
*/
_:
let
  CryptsetupModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.cryptsetup.extended;
    in
    {
      options.programs.cryptsetup.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable cryptsetup.";
        };

        package = lib.mkPackageOption pkgs "cryptsetup" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.cryptsetup = CryptsetupModule;
}
