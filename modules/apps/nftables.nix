/*
  Package: nftables
  Description: Project that aims to replace the existing {ip,ip6,arp,eb}tables framework.
  Homepage: https://netfilter.org/projects/nftables/
  Documentation: https://netfilter.org/projects/nftables/

  Summary:
    * Provides the `nft` CLI for defining packet filtering, NAT, and traffic classification rulesets.
    * Unifies IPv4, IPv6, ARP, and bridge filtering under a single rules language and kernel API.

  Options:
    -f: Load a ruleset from a file.
    list ruleset: Print the active nftables ruleset.
    flush ruleset: Remove all active tables, chains, and rules.
*/
_:
let
  NftablesModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.nftables.extended;
    in
    {
      options.programs.nftables.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable nftables.";
        };

        package = lib.mkPackageOption pkgs "nftables" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.nftables = NftablesModule;
}
