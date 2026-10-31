/*
  Package: pcscd
  Description: PCSC-Lite daemon for smart card access.
  Homepage: https://pcsclite.apdu.fr/
  Documentation: https://pcsclite.apdu.fr/api/
  Repository: https://salsa.debian.org/rousseau/PCSC

  Summary:
    * Serves smart cards to PC/SC clients such as OpenSC and GnuPG.
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
