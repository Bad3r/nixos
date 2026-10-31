/*
  Package: bzmenu
  Description: Launcher-driven Bluetooth manager for Linux.
  Homepage: https://github.com/e-tho/bzmenu
  Documentation: https://github.com/e-tho/bzmenu/blob/main/README.md
  Repository: https://github.com/e-tho/bzmenu

  Summary:
    * Drives a user-chosen launcher (dmenu, rofi, fuzzel, bemenu, walker, custom stdin) to manage BlueZ adapters and devices.
    * Talks directly to bluetoothd over D-Bus and emits desktop notifications for pairing prompts and operation results.

  Options:
    --launcher <name>: Select the launcher backend; supported values are dmenu, rofi, fuzzel, bemenu, walker, custom.
    -i <mode>: Pick the icon style (`font` for NerdFonts glyphs or `xdg` for XDG icon theme).

  Notes:
    * Needs BlueZ and a notification daemon.
*/
_:
let
  BzmenuModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.bzmenu.extended;
    in
    {
      options.programs.bzmenu.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable bzmenu.";
        };

        package = lib.mkPackageOption pkgs "bzmenu" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.bzmenu = BzmenuModule;
}
