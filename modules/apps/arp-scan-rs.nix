/*
  Package: arp-scan-rs
  Description: ARP scan tool for fast local network scans.
  Homepage: https://github.com/kongbytes/arp-scan-rs
  Documentation: https://github.com/kongbytes/arp-scan-rs#readme
  Repository: https://github.com/kongbytes/arp-scan-rs

  Summary:
    * Discovers IPv4 hosts on local Layer-2 networks with configurable scan profiles.
    * Emits plain, JSON, YAML, or CSV output and supports VLAN, OUI, and custom ARP packet fields.

  Options:
    --profile <name>: Select default, fast, stealth, or chaos scan profile defaults.
    --interface <iface>: Use a specific network interface instead of auto-selecting one.
    --network <range>: Scan explicit IPv4 ranges, CIDR networks, or comma-separated targets.
    --output <format>: Emit plain, JSON, YAML, or CSV output.
    --vlan <id>: Send ARP requests using an 802.1Q VLAN tag.

  Notes:
    * The package name is `arp-scan-rs`, but the installed binary is `arp-scan`.
    * Installs a capability wrapper so `wheel` users can send ARP requests without invoking `sudo`.
*/
_:
let
  ArpScanRsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."arp-scan-rs".extended;
    in
    {
      options.programs.arp-scan-rs.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable arp-scan-rs.";
        };

        package = lib.mkPackageOption pkgs "arp-scan-rs" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];

        security.wrappers.arp-scan = {
          source = "${cfg.package}/bin/arp-scan";
          capabilities = "cap_net_raw+ep";
          owner = "root";
          group = "wheel";
          permissions = "u+rx,g+x";
        };
      };
    };
in
{
  flake.nixosModules.apps.arp-scan-rs = ArpScanRsModule;
}
