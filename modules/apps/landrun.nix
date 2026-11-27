/*
  Package: landrun
  Description: Sandbox for running Linux processes with Landlock LSM.
  Homepage: https://github.com/Zouuup/landrun
  Documentation: https://github.com/Zouuup/landrun#readme
  Repository: https://github.com/Zouuup/landrun

  Summary:
    * Restricts filesystem and network access of a command through Landlock, without root.
    * Denies everything by default; each allowed path or port is granted explicitly.

  Options:
    --ro <PATH>: Allow read-only access to a path.
    --rw <PATH>: Allow read-write access to a path.
    --rox <PATH>: Allow read and execute access to a path.
    --rwx <PATH>: Allow read, write, and execute access to a path.
    --bind-tcp <PORT>: Allow binding to a TCP port.
    --connect-tcp <PORT>: Allow connecting to a TCP port.
    --env <NAME>: Pass an environment variable into the sandbox.
    --best-effort: Degrade gracefully on kernels with an older Landlock ABI.
*/
_:
let
  LandrunModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.landrun.extended;
    in
    {
      options.programs.landrun.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable landrun.";
        };

        package = lib.mkPackageOption pkgs "landrun" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.landrun = LandrunModule;
}
