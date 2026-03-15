/*
  Package: iptables
  Description: Program to configure the Linux IP packet filtering ruleset.
  Homepage: https://www.netfilter.org/projects/iptables/index.html
  Documentation: https://www.netfilter.org/projects/iptables/index.html

  Summary:
    * Configures legacy Netfilter packet filtering, NAT, and mangle tables from the command line.
    * Supports scripted firewall updates, rule inspection, and chain management for IPv4 filtering workflows.

  Options:
    -A: Append a rule to the selected chain.
    -D: Delete a matching rule from the selected chain.
    -L: List rules in the selected table or chain.
    -t: Select a non-default table such as `nat`, `mangle`, or `raw`.
*/
_:
let
  IptablesModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.iptables.extended;
    in
    {
      options.programs.iptables.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable iptables.";
        };

        package = lib.mkPackageOption pkgs "iptables" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.iptables = IptablesModule;
}
