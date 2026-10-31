/*
  Package: wireguard-tools
  Description: Command-line utilities (`wg`, `wg-quick`) for managing WireGuard VPN tunnels.
  Homepage: https://www.wireguard.com/
  Documentation: https://www.wireguard.com/quickstart/
  Repository: https://git.zx2c4.com/wireguard-tools/

  Summary:
    * `wg` generates keys, manages peers, and reports tunnel status.
    * `wg-quick` brings tunnels up and down from `/etc/wireguard/*.conf` files.

  Options:
    wg genkey | wg pubkey: Generate private/public key pairs.
    wg show: Display interface and peer status.
    wg set <interface> <options>: Adjust peers and settings at runtime.
    wg-quick up <config>: Bring up a tunnel defined in `/etc/wireguard/<config>.conf`.
    wg-quick down <config>: Tear down a tunnel.
*/
_:
let
  WireguardToolsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."wireguard-tools".extended;
    in
    {
      options.programs.wireguard-tools.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable wireguard-tools.";
        };

        package = lib.mkPackageOption pkgs "wireguard-tools" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.wireguard-tools = WireguardToolsModule;
}
