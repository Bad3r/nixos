/*
  Package: procps
  Description: procps-ng suite of process monitoring and system utilities.
  Homepage: https://gitlab.com/procps-ng/procps
  Documentation: https://gitlab.com/procps-ng/procps/-/wikis/home
  Repository: https://gitlab.com/procps-ng/procps

  Summary:
    * Provides commands such as `ps`, `top`, `vmstat`, `free`, and `watch` for inspecting system state.
    * Aggregates kernel metrics for capacity planning, troubleshooting, and automation scripts.

  Options:
    --sort=-pcpu: Arrange `ps --sort` output by CPU usage to spot hotspots quickly.
    -H: Display individual threads in `top -H` for fine-grained inspection.
    -n <seconds>: Set the refresh interval when running `watch -n` on frequently polled commands.
*/
_:
let
  ProcpsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.procps.extended;
    in
    {
      options.programs.procps.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable procps.";
        };

        package = lib.mkPackageOption pkgs "procps" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.procps = ProcpsModule;
}
