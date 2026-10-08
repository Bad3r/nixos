/*
  Package: ethtool
  Description: Utility for querying and changing network device driver and hardware settings.
  Homepage: https://www.kernel.org/pub/software/network/ethtool/
  Documentation: https://man7.org/linux/man-pages/man8/ethtool.8.html
  Repository: https://git.kernel.org/pub/scm/network/ethtool/ethtool.git

  Summary:
    * Reports link speed, duplex, autonegotiation, driver and firmware versions, offload state, and adapter statistics.
    * Changes link settings, offloads, ring sizes, and Wake-on-LAN; changes need `CAP_NET_ADMIN`.

  Options:
    -i <dev>: Show driver and firmware information.
    -P <dev>: Show the permanent hardware address.
    -S <dev>: Show adapter statistics.
    -k <dev>: Show protocol offload and other feature states.
    -s <dev> wol <modes>: Change the Wake-on-LAN modes.
*/
_:
let
  EthtoolModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.ethtool.extended;
    in
    {
      options.programs.ethtool.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable ethtool.";
        };

        package = lib.mkPackageOption pkgs "ethtool" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.ethtool = EthtoolModule;
}
