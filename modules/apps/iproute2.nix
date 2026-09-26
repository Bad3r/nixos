/*
  Package: iproute2
  Description: Linux utilities for controlling TCP/IP networking, routing, sockets, and traffic control.
  Homepage: https://wiki.linuxfoundation.org/networking/iproute2
  Documentation: https://man7.org/linux/man-pages/man8/ip.8.html
  Repository: https://git.kernel.org/pub/scm/network/iproute2/iproute2.git

  Summary:
    * `ip` manages addresses, links, routes, neighbours, policy rules, tunnels, and network namespaces.
    * `ss` inspects sockets, `tc` configures traffic control, and `bridge` manages bridge ports and forwarding entries.

  Options:
    ip -br address: Print one brief line of addresses per interface.
    ip route get <addr>: Show the route the kernel selects for a destination.
    ip netns list: List named network namespaces.
    ss -tulpn: List listening TCP and UDP sockets numerically with their owning processes.
    tc qdisc show: Show the queueing disciplines attached to each interface.
*/
_:
let
  Iproute2Module =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.iproute2.extended;
    in
    {
      options.programs.iproute2.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable iproute2.";
        };

        package = lib.mkPackageOption pkgs "iproute2" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.iproute2 = Iproute2Module;
}
