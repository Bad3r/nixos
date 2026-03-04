/*
  Package: pcscd
  Description: PCSC-Lite daemon for smart card access.
  Homepage: https://pcsclite.apdu.fr/
  Documentation: https://pcsclite.apdu.fr/api/
  Repository: https://salsa.debian.org/rousseau/PCSC

  Summary:
    * Enables the smart-card daemon used by PC/SC clients such as OpenSC and GnuPG.
    * Uses services namespace because pcscd runs as a system service.
*/
_:
let
  PcscdModule =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.services.pcscd.extended;
    in
    {
      options.services.pcscd.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable pcscd.";
        };
      };

      config = lib.mkIf cfg.enable {
        services.pcscd.enable = true;
      };
    };
in
{
  flake.nixosModules.apps.pcscd = PcscdModule;
}
