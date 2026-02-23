/*
  Package: fuse-overlayfs
  Description: FUSE-based overlay filesystem implementation for unprivileged and rootless environments.
  Homepage: https://github.com/containers/fuse-overlayfs
  Documentation: https://github.com/containers/fuse-overlayfs#readme
  Repository: https://github.com/containers/fuse-overlayfs

  Summary:
    * Implements overlay filesystem semantics in userspace, enabling lower/upper/workdir layering without kernel overlayfs privileges.
    * Supports game and container workflows that require writable overlays on top of read-only base assets.

  Options:
    -o lowerdir=<path>,upperdir=<path>,workdir=<path>: Compose layered filesystem views from immutable and writable directories.
    -o squash_to_uid=<uid>: Remap ownership on overlay output to match the current user.
    -o squash_to_gid=<gid>: Remap group ownership for compatibility with user-managed content directories.
*/
_:
let
  FuseOverlayfsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."fuse-overlayfs".extended;
    in
    {
      options.programs.fuse-overlayfs.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable fuse-overlayfs.";
        };

        package = lib.mkPackageOption pkgs "fuse-overlayfs" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.fuse-overlayfs = FuseOverlayfsModule;
}
