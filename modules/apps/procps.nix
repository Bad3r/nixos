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
    ps aux: List all processes with CPU and memory usage statistics.
    top -H: Show individual threads in the interactive top view.
    watch -n <seconds> <command>: Periodically execute a command and refresh the display.
*/

{
  flake.nixosModules.apps.procps =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.procps ];
    };
}
