/*
  Package: gphoto2
  Description: Command-line PTP client for downloading media from cameras and iOS devices.
  Homepage: https://www.gphoto.org/
  Documentation: https://www.gphoto.org/doc/
  Repository: https://github.com/gphoto/gphoto2

  Summary:
    * Downloads photos and videos over PTP, the protocol iPhones expose for camera-roll access after the on-device photo permission prompt.
    * Adds a scriptable batch-import path (filename templates, only-new filtering) that the gvfs gphoto2 GUI backend does not offer.

  Options:
    --auto-detect: List detected cameras and PTP devices.
    --list-files: Enumerate files on the device storage.
    --get-all-files: Download everything from the current folder tree.
    --new: Restrict operations to files not previously downloaded.
    --filename <pattern>: Name downloads with strftime and counter placeholders.

  Notes:
    * Talks libgphoto2/libusb directly and does not use usbmuxd; the device must stay unlocked during transfers.
    * PTP access to iOS devices is read-only by design; deleting after transfer is the only write operation iOS permits.
*/
_:
let
  Gphoto2Module =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.gphoto2.extended;
    in
    {
      options.programs.gphoto2.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable gphoto2.";
        };

        package = lib.mkPackageOption pkgs "gphoto2" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.gphoto2 = Gphoto2Module;
}
