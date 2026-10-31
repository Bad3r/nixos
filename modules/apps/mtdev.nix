/*
  Package: mtdev
  Description: Multitouch Protocol Translation Library.
  Homepage: https://bitmath.se/org/code/mtdev/
  Documentation: https://bitmath.se/org/code/mtdev/
  Repository: https://bitmath.se/org/git/mtdev.git/

  Summary:
    * Translates Linux kernel multitouch events into the slotted type B protocol.
    * Supports type A and type B multitouch devices with or without contact tracking.
*/
_:
let
  MtdevModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.mtdev.extended;
    in
    {
      options.programs.mtdev.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable mtdev.";
        };

        package = lib.mkPackageOption pkgs "mtdev" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.mtdev = MtdevModule;
}
