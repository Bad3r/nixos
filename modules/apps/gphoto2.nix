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
    * Installs libgphoto2's udev rules, the only source of the ID_GPHOTO2 property gvfs keys on to offer the camera volume, and creates the "camera" group they hardcode. Stock systemd 70-uaccess.rules already ACLs PTP-class devices to the active local seat, so the group grant covers non-seat access such as SSH, and only that path needs a fresh login.
    * gvfs runs its own gphoto2 volume monitor against the same libgphoto2; only one process can claim the PTP port, so the monitor has to be stopped before a CLI transfer.
*/
_:
let
  Gphoto2Module =
    {
      config,
      lib,
      metaOwner,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.gphoto2.extended;
      owner = metaOwner.username or null;
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

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          {
            assertions = [
              {
                assertion = owner != null;
                message = "gphoto2 module: expected metaOwner.username to be defined";
              }
            ];

            environment.systemPackages = [ cfg.package ];

            # The shipped rules set ID_GPHOTO2, which gvfs keys on to offer the
            # camera volume, and group-gate the device to "camera". Stock
            # 70-uaccess.rules already ACLs PTP-class devices to the active
            # seat, so the group covers non-seat access only.
            services.udev.packages = [ pkgs.libgphoto2 ];
            users.groups.camera = { };
          }

          (lib.mkIf (owner != null) {
            users.users.${owner}.extraGroups = lib.mkAfter [ "camera" ];
          })
        ]
      );
    };
in
{
  flake.nixosModules.apps.gphoto2 = Gphoto2Module;
}
