/*
  Package: udiskie
  Description: UDisks2 front-end for automounting and tray notifications of removable drives.
  Homepage: https://github.com/coldfix/udiskie
  Documentation: https://github.com/coldfix/udiskie#readme
  Repository: https://github.com/coldfix/udiskie

  Summary:
    * Monitors UDisks2 for removable media, auto-mounting devices, prompting for encryption passwords, and providing system tray control.
    * Offers CLI tools to mount/unmount devices, manage LUKS passphrases, and configure rules via YAML.

  Options:
    udiskie --tray: Start with a tray icon for interactive control.
    udiskie-mount <device>: Manually mount a device managed by UDisks2.
    udiskie-umount <device>: Unmount a device.
    --appindicator: Use AppIndicator instead of legacy tray icons.
    --notify: Enable desktop notifications (default).

  Example Usage:
    * `udiskie --tray {PRESERVED_DOCUMENTATION}` -- Run udiskie in the background to automount USB drives with a tray icon.
    * `udiskie-mount -a` -- Mount all currently available devices.
    * Customize `~/.config/udiskie/config.yml` to specify mount options or blacklist devices.
*/
_:
let
  UdiskieModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.udiskie.extended;
    in
    {
      options.programs.udiskie.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable udiskie.";
        };

        package = lib.mkPackageOption pkgs "udiskie" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.udiskie = UdiskieModule;
}
