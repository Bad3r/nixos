/*
  Package: sshfs
  Description: FUSE-based filesystem that allows remote filesystems to be mounted over SSH.
  Homepage: https://github.com/libfuse/sshfs
  Documentation: https://github.com/libfuse/sshfs
  Repository: https://github.com/libfuse/sshfs

  Summary:
    * Mounts remote directories over SSH through FUSE so they appear as local filesystems.
    * Supports reconnects, caching, alternate SSH commands, and standard FUSE mount controls.

  Options:
    -p PORT: Connect to a non-default SSH port.
    -F ssh_configfile: Use an alternate SSH client configuration file.
    -o reconnect: Reconnect automatically if the SSH session drops.
    -o ssh_command=CMD: Run a specific SSH client command instead of the default ssh binary.
    -o allow_other: Allow users other than the mounter to access the mounted filesystem.
    -o direct_io: Bypass page cache for direct I/O on the mount.
*/
_:
let
  SshfsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.sshfs.extended;
    in
    {
      options.programs.sshfs.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable sshfs.";
        };

        package = lib.mkPackageOption pkgs "sshfs" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.sshfs = SshfsModule;
}
