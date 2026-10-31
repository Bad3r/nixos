/*
  Package: f3
  Description: Fight Flash Fraud toolkit for testing and repairing USB flash drives and SD cards.
  Homepage: https://fight-flash-fraud.readthedocs.io/en/stable/
  Documentation: https://fight-flash-fraud.readthedocs.io/en/stable/
  Repository: https://github.com/AltraMayor/f3

  Summary:
    * Detects counterfeit or damaged flash media by measuring real capacity and locating bad sectors.
    * Repartitions fake drives down to their real capacity.

  Options:
    f3probe --destructive <device>: Run a fast destructive test for real capacity and bad blocks.
    f3fix --last-sec=<sector> <device>: Repartition the drive to cover only its real capacity.
*/
_:
let
  F3Module =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.f3.extended;
    in
    {
      options.programs.f3.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable f3.";
        };

        package = lib.mkPackageOption pkgs "f3" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.f3 = F3Module;
}
