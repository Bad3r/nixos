/*
  Package: virt-viewer
  Description: SPICE and VNC console client for libvirt guests.
  Homepage: https://gitlab.com/virt-viewer/virt-viewer
  Documentation: https://gitlab.com/virt-viewer/virt-viewer
  Repository: https://gitlab.com/virt-viewer/virt-viewer

  Summary:
    * `virt-viewer` attaches to a libvirt guest's graphical console by name.
    * `remote-viewer` opens a SPICE or VNC URI, or a .vv connection file.

  Example Usage:
    * `virt-viewer --connect qemu:///system <guest>` -- Open a system guest's console.
    * `remote-viewer spice://127.0.0.1:5900` -- Attach to a SPICE server directly.
*/
_:
let
  VirtViewerModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."virt-viewer".extended;
    in
    {
      options.programs."virt-viewer".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable virt-viewer.";
        };

        package = lib.mkPackageOption pkgs "virt-viewer" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."virt-viewer" = VirtViewerModule;
}
