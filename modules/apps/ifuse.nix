/*
  Package: ifuse
  Description: FUSE filesystem for mounting iPhone and iPad storage over AFC.
  Homepage: https://libimobiledevice.org/
  Documentation: https://github.com/libimobiledevice/ifuse#readme
  Repository: https://github.com/libimobiledevice/ifuse

  Summary:
    * Mounts the media filesystem (DCIM, Downloads, recordings) of a paired iOS device as a regular directory.
    * Reaches per-app Documents folders through the house_arrest service for apps that opt into file sharing.

  Options:
    --documents <appid>: Mount the named app's Documents folder instead.
    --list-apps: List installed apps and their file-sharing capability.
    -u <udid>: Select a specific device when several are connected.

  Notes:
    * Unmount with `fusermount3 -u <mountpoint>`.
    * A locked or untrusted device fails to mount.
    * AFC transfers run at roughly 2-20 MB/s.
    * Needs the usbmuxd daemon.
*/
_:
let
  IfuseModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.ifuse.extended;
    in
    {
      options.programs.ifuse.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable ifuse.";
        };

        package = lib.mkPackageOption pkgs "ifuse" { };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = config.services.usbmuxd.enable;
            message = "programs.ifuse.extended.enable requires the usbmuxd daemon; enable services.usbmuxd.extended.enable.";
          }
        ];

        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.ifuse = IfuseModule;
}
