/*
  Package: vial
  Description: GUI that remaps keyboards running Vial firmware, live over USB.
  Homepage: https://get.vial.today
  Documentation: https://get.vial.today/manual/
  Repository: https://github.com/vial-kb/vial-gui

  Summary:
    * Edits keymaps, layers, macros, and other runtime settings on a connected board, which applies them immediately.
    * Needs raw HID access to the board; the package's bundled udev rule stays inactive because NixOS reads rules only from `services.udev.packages`, so a keyboard module such as `modules/hardware/keyboards/fc660c.nix` grants it.

  Options:
    Vial: Open the configurator, which detects connected Vial boards.
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
