/*
  Package: bandwhich
  Description: Terminal bandwidth utilization tool that attributes network traffic to processes, connections, and remote hosts.
  Homepage: https://github.com/imsnif/bandwhich
  Documentation: https://github.com/imsnif/bandwhich#readme
  Repository: https://github.com/imsnif/bandwhich

  Summary:
    * Sniffs a network interface and shows current utilization per process, connection, and remote address.
    * Resolves remote addresses through reverse DNS and offers a raw, machine-readable output mode.

  Options:
    -i, --interface <name>: Listen on a specific network interface.
    -r, --raw: Print machine-readable output instead of the TUI.
    -n, --no-resolve: Skip reverse DNS lookups of remote addresses.
    -p, --processes: Show only the processes table.
    -t, --total-utilization: Show cumulative usage instead of the current rate.

  Notes:
    * `wheel` users run it without `sudo`.
*/
_:
let
  BandwhichModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.bandwhich.extended;
    in
    {
      options.programs.bandwhich.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable bandwhich.";
        };

        package = lib.mkPackageOption pkgs "bandwhich" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];

        security.wrappers.bandwhich = {
          source = "${cfg.package}/bin/bandwhich";
          capabilities = "cap_sys_ptrace,cap_dac_read_search,cap_net_raw,cap_net_admin+ep";
          owner = "root";
          group = "wheel";
          permissions = "u+rx,g+x";
        };
      };
    };
in
{
  flake.nixosModules.apps.bandwhich = BandwhichModule;
}
