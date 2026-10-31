/*
  Package: vial
  Description: GUI that remaps keyboards running Vial firmware, live over USB.
  Homepage: https://get.vial.today
  Documentation: https://get.vial.today/manual/
  Repository: https://github.com/vial-kb/vial-gui

  Summary:
    * Edits keymaps, layers, and macros on a connected board, which applies them immediately.

  Notes:
    * Raw HID access comes from a keyboard module, such as `modules/hardware/keyboards/fc660c.nix`.
*/
_:
let
  VialModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.vial.extended;
    in
    {
      options.programs.vial.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable vial.";
        };

        package = lib.mkPackageOption pkgs "vial" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.vial = VialModule;
}
